# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketRatingsController < ApplicationController
  prepend_before_action :authentication_check

  # GET /api/v1/ticket_ratings/:ticket_id
  def show
    ticket = Ticket.lookup(id: params[:ticket_id])
    return render json: { error: 'Ticket not found' }, status: :not_found if ticket.blank?

    closed = ticket_closed?(ticket)
    agents = TicketRating.participating_agents(ticket)

    existing_records = TicketRating.where(ticket_id: ticket.id)
    has_rated = existing_records.exists?

    agent_ids = existing_records.map(&:agent_id).uniq
    agents_by_id = User.where(id: agent_ids).index_by(&:id)

    existing = existing_records.index_by(&:agent_id).transform_values do |r|
      agent = agents_by_id[r.agent_id]
      {
        rating: r.rating,
        comment: r.comment,
        created_at: r.created_at,
        created_at_formatted: r.created_at ? r.created_at.in_time_zone.strftime('%d %b %Y, %H:%M') : '',
        agent_id: r.agent_id,
        agent_name: agent ? (agent.fullname.presence || agent.firstname) : 'Petugas Support'
      }
    end

    render json: {
      ticket_id: ticket.id,
      ticket_number: ticket.number,
      is_closed: closed,
      has_rated: has_rated,
      can_rate: closed && (current_user.id == ticket.customer_id) && !has_rated,
      participating_agents: agents.map do |a|
        {
          id: a.id,
          firstname: a.firstname,
          lastname: a.lastname,
          fullname: a.fullname,
          email: a.email,
          average_rating: a.average_rating.to_f,
          total_ratings: a.total_ratings.to_i
        }
      end,
      existing_ratings: existing
    }, status: :ok
  end

  # POST /api/v1/ticket_ratings
  def create
    ticket = Ticket.lookup(id: params[:ticket_id])
    return render json: { error: 'Ticket not found' }, status: :not_found if ticket.blank?

    unless ticket_closed?(ticket)
      return render json: { error: 'Rating hanya dapat diberikan setelah tiket ditutup (closed).' }, status: :unprocessable_entity
    end

    unless current_user.id == ticket.customer_id
      return render json: { error: 'Hanya customer pemilik tiket yang berhak memberikan ulasan.' }, status: :forbidden
    end

    # Prevent double rating
    if TicketRating.where(ticket_id: ticket.id, customer_id: ticket.customer_id).exists?
      return render json: { error: 'Penilaian untuk tiket ini sudah pernah dikirimkan dan tidak dapat diubah kembali.' }, status: :unprocessable_entity
    end

    ratings_input = params[:ratings]
    ratings_map = normalize_ratings_input(ratings_input)

    if ratings_map.blank?
      return render json: { error: 'Data rating tidak boleh kosong.' }, status: :unprocessable_entity
    end

    # Validasi bahwa agent yang dinilai memang berpartisipasi
    allowed_agent_ids = TicketRating.participating_agents(ticket).pluck(:id)
    saved_records = []

    ActiveRecord::Base.transaction do
      ratings_map.each do |agent_id_str, data|
        agent_id = agent_id_str.to_i
        next unless allowed_agent_ids.include?(agent_id)

        rating_val = (data[:rating] || data['rating']).to_i
        next if rating_val < 1 || rating_val > 5

        comment_val = (data[:comment] || data['comment']).to_s.strip
        comment_val = nil if comment_val.blank?

        record = TicketRating.new(
          ticket_id: ticket.id,
          agent_id: agent_id,
          customer_id: ticket.customer_id,
          rating: rating_val,
          comment: comment_val
        )
        record.save!
        saved_records << record
      end
    end

    render json: {
      success: true,
      message: 'Rating berhasil disimpan.',
      saved_count: saved_records.count
    }, status: :ok
  end

  # GET /api/v1/agent_rating/:user_id
  def agent_summary
    user = User.lookup(id: params[:user_id])
    return render json: { error: 'User not found' }, status: :not_found if user.blank?

    is_agent = user.roles.where(name: ['Admin', 'Agent']).any?
    unless is_agent
      return render json: {
        is_agent: false,
        id: user.id,
        fullname: user.fullname,
        message: 'Pengguna bukan merupakan agent atau admin.'
      }, status: :ok
    end

    distribution = TicketRating.where(agent_id: user.id).group(:rating).count
    ratings = TicketRating.where(agent_id: user.id)
                          .includes(:customer, :ticket)
                          .order(created_at: :desc)
                          .limit(50)

    reviews_list = ratings.map do |r|
      cust_name = r.customer ? (r.customer.fullname.presence || r.customer.firstname.presence || 'Customer') : 'Customer'
      {
        id: r.id,
        rating: r.rating,
        comment: r.comment.to_s,
        created_at: r.created_at.strftime('%d %b %Y, %H:%M'),
        ticket_id: r.ticket_id,
        ticket_number: r.ticket&.number || r.ticket_id,
        ticket_title: r.ticket&.title || '',
        customer_name: cust_name,
        customer_initial: cust_name.strip.first.upcase
      }
    end

    role_names = user.roles.map(&:name)
    display_role = if role_names.include?('Admin')
                     'Administrator'
                   elsif role_names.include?('Agent')
                     'Petugas Support / Agent'
                   else
                     'Staff Pelayanan'
                   end

    render json: {
      is_agent: true,
      id: user.id,
      fullname: user.fullname,
      firstname: user.firstname,
      lastname: user.lastname,
      email: user.email,
      role_name: display_role,
      average_rating: user.average_rating.to_f,
      total_ratings: user.total_ratings.to_i,
      distribution: {
        5 => distribution[5] || 0,
        4 => distribution[4] || 0,
        3 => distribution[3] || 0,
        2 => distribution[2] || 0,
        1 => distribution[1] || 0
      },
      reviews: reviews_list
    }, status: :ok
  end

  private

  def ticket_closed?(ticket)
    return false if ticket.blank? || ticket.state_id.blank?

    state = Ticket::State.lookup(id: ticket.state_id)
    return false if state.blank?

    state_type = Ticket::StateType.lookup(id: state.state_type_id)
    state_type&.name == 'closed'
  end

  def normalize_ratings_input(input)
    case input
    when ActionController::Parameters, Hash
      input.to_unsafe_h
    when Array
      map = {}
      input.each do |item|
        h = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item
        aid = h[:agent_id] || h['agent_id']
        map[aid] = h if aid.present?
      end
      map
    else
      {}
    end
  end
end

