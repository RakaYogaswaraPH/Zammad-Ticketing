# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class SlaReportsController < ApplicationController
  prepend_before_action :authentication_check
  before_action :authorize_staff!, except: [:ticket_sla]

  # GET /api/v1/sla_reports/summary
  def summary
    scope = filtered_closed_tickets

    raw_stats = scope.pick(
      Arel.sql('COUNT(tickets.id)'),
      Arel.sql('AVG(tickets.close_in_min)'),
      Arel.sql('MIN(tickets.close_in_min)'),
      Arel.sql('MAX(tickets.close_in_min)'),
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min <= 60)'),
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min <= 1440)')
    )

    count = raw_stats ? raw_stats[0].to_i : 0
    if count.zero?
      return render json: {
        total_closed: 0,
        average_duration_min: 0,
        average_duration_human: '0 menit',
        min_duration_min: 0,
        min_duration_human: '0 menit',
        max_duration_min: 0,
        max_duration_human: '0 menit',
        under_1_hour_count: 0,
        under_24_hours_count: 0,
        sla_compliance_rate: 100.0
      }, status: :ok
    end

    avg_min = raw_stats[1].to_f.round(1)
    min_min = raw_stats[2].to_i
    max_min = raw_stats[3].to_i
    under_1h = raw_stats[4].to_i
    under_24h = raw_stats[5].to_i
    compliance = ((under_24h.to_f / count) * 100).round(1)

    render json: {
      total_closed: count,
      average_duration_min: avg_min,
      average_duration_human: format_duration(avg_min),
      min_duration_min: min_min,
      min_duration_human: format_duration(min_min),
      max_duration_min: max_min,
      max_duration_human: format_duration(max_min),
      under_1_hour_count: under_1h,
      under_24_hours_count: under_24h,
      sla_compliance_rate: compliance
    }, status: :ok
  end

  # GET /api/v1/sla_reports/chart_data
  def chart_data
    scope = filtered_closed_tickets

    # 1. Daily Trend: Group by DATE(tickets.close_at)
    daily_stats = scope.where.not(tickets: { close_at: nil })
                       .group(Arel.sql('DATE(tickets.close_at)'))
                       .order(Arel.sql('DATE(tickets.close_at) ASC'))
                       .pluck(Arel.sql('DATE(tickets.close_at)'), Arel.sql('AVG(tickets.close_in_min)'), Arel.sql('COUNT(tickets.id)'))

    daily_labels = []
    daily_avg_hours = []
    daily_avg_minutes = []
    daily_counts = []

    daily_stats.each do |date, avg_min, count|
      d_str = date.is_a?(Date) ? date.strftime('%d %b') : date.to_s
      daily_labels << d_str
      daily_avg_hours << (avg_min.to_f / 60.0).round(2)
      daily_avg_minutes << avg_min.to_f.round(1)
      daily_counts << count
    end

    # 2. Distribution Buckets (Single optimized query instead of 5 separate counts)
    dist_stats = scope.pick(
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min < 60)'),
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min >= 60 AND tickets.close_in_min < 240)'),
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min >= 240 AND tickets.close_in_min < 1440)'),
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min >= 1440 AND tickets.close_in_min < 4320)'),
      Arel.sql('COUNT(*) FILTER (WHERE tickets.close_in_min >= 4320)')
    )

    buckets = {
      '< 1 Jam'    => dist_stats ? dist_stats[0].to_i : 0,
      '1 - 4 Jam'  => dist_stats ? dist_stats[1].to_i : 0,
      '4 - 24 Jam' => dist_stats ? dist_stats[2].to_i : 0,
      '1 - 3 Hari' => dist_stats ? dist_stats[3].to_i : 0,
      '> 3 Hari'   => dist_stats ? dist_stats[4].to_i : 0
    }

    # 3. By Group
    group_stats = scope.joins(:group)
                       .group('groups.id, groups.name')
                       .order('COUNT(tickets.id) DESC')
                       .pluck('groups.id', 'groups.name', Arel.sql('AVG(tickets.close_in_min)'), Arel.sql('COUNT(tickets.id)'))

    by_group = group_stats.map do |gid, gname, avg_min, count|
      {
        id: gid,
        name: gname,
        avg_hours: (avg_min.to_f / 60.0).round(2),
        avg_human: format_duration(avg_min),
        count: count
      }
    end

    # 4. By Priority
    priority_stats = scope.joins(:priority)
                          .group('ticket_priorities.id, ticket_priorities.name')
                          .order('ticket_priorities.id ASC')
                          .pluck('ticket_priorities.id', 'ticket_priorities.name', Arel.sql('AVG(tickets.close_in_min)'), Arel.sql('COUNT(tickets.id)'))

    by_priority = priority_stats.map do |pid, pname, avg_min, count|
      {
        id: pid,
        name: pname,
        avg_hours: (avg_min.to_f / 60.0).round(2),
        avg_human: format_duration(avg_min),
        count: count
      }
    end

    render json: {
      daily_trend: {
        labels: daily_labels,
        avg_hours: daily_avg_hours,
        avg_minutes: daily_avg_minutes,
        counts: daily_counts
      },
      distribution: buckets,
      by_group: by_group,
      by_priority: by_priority
    }, status: :ok
  end

  # GET /api/v1/sla_reports/tickets
  def tickets
    scope = filtered_closed_tickets

    # Search keyword filter
    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      scope = scope.where('tickets.number ILIKE ? OR tickets.title ILIKE ?', q, q)
    end

    page = [params[:page].to_i, 1].max
    per_page = 20
    total_count = scope.count

    tickets_page = scope.includes(:customer, :owner, :group, :priority)
                        .order(close_at: :desc)
                        .offset((page - 1) * per_page)
                        .limit(per_page)

    data = tickets_page.map do |t|
      eff_close = t.last_close_at || t.close_at || t.updated_at
      mins = t.close_in_min || [((eff_close - t.created_at) / 60).round, 0].max

      {
        id: t.id,
        number: t.number,
        title: t.title,
        customer_name: t.customer ? (t.customer.fullname.presence || t.customer.firstname.presence || 'Customer') : '-',
        owner_name: t.owner ? (t.owner.fullname.presence || t.owner.firstname.presence || 'Unassigned') : 'Unassigned',
        group_name: t.group&.name || '-',
        priority_name: t.priority&.name || 'Normal',
        created_at: t.created_at.strftime('%d %b %Y, %H:%M'),
        close_at: eff_close.strftime('%d %b %Y, %H:%M'),
        duration_min: mins,
        duration_human: format_duration(mins),
        first_response_min: t.first_response_in_min,
        first_response_human: t.first_response_in_min ? format_duration(t.first_response_in_min) : '-'
      }
    end

    render json: {
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: (total_count.to_f / per_page).ceil,
      tickets: data
    }, status: :ok
  end

  # GET /api/v1/sla_reports/filters_meta
  def filters_meta
    groups = Group.where(active: true).order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    priorities = Ticket::Priority.where(active: true).order(:id).pluck(:id, :name).map { |id, name| { id: id, name: name } }

    render json: {
      groups: groups,
      priorities: priorities
    }, status: :ok
  end

  # GET /api/v1/sla_reports/ticket_sla/:id
  def ticket_sla
    ticket = Ticket.find_by(id: params[:id])
    return render json: { error: 'Tiket tidak ditemukan' }, status: :not_found unless ticket

    # Allow staff only (Admin/Agent) - NOT customer
    is_staff = current_user.roles.where(name: ['Admin', 'Agent']).any? ||
               (current_user.respond_to?(:permissions?) && (current_user.permissions?('ticket.agent') || current_user.permissions?('admin') || current_user.permissions?('report')))

    return render json: { error: 'Akses ditolak' }, status: :forbidden unless is_staff

    is_closed = (ticket.state.name == 'closed')
    eff_close = ticket.last_close_at || ticket.close_at || (is_closed ? ticket.updated_at : nil)

    now = Time.zone.now
    mins = if is_closed
             ticket.close_in_min || [((eff_close - ticket.created_at) / 60).round, 0].max
           else
             [((now - ticket.created_at) / 60).round, 0].max
           end

    render json: {
      ticket_id: ticket.id,
      number: ticket.number,
      title: ticket.title,
      is_closed: is_closed,
      state: ticket.state.name,
      state_human: is_closed ? 'Ditutup / Selesai' : 'Sedang Diproses',
      created_at: ticket.created_at.strftime('%d %b %Y, %H:%M'),
      created_at_iso: ticket.created_at.iso8601,
      created_at_ms: (ticket.created_at.to_f * 1000).to_i,
      close_at: eff_close ? eff_close.strftime('%d %b %Y, %H:%M') : nil,
      close_at_iso: eff_close ? eff_close.iso8601 : nil,
      close_at_ms: eff_close ? (eff_close.to_f * 1000).to_i : nil,
      server_now_ms: (now.to_f * 1000).to_i,
      duration_min: mins,
      duration_human: format_duration(mins),
      first_response_min: ticket.first_response_in_min,
      first_response_human: ticket.first_response_in_min ? format_duration(ticket.first_response_in_min) : nil
    }, status: :ok
  end

  private

  def filtered_closed_tickets
    scope = Ticket.joins(:state).where(ticket_states: { name: 'closed' })

    if params[:from].present?
      from_date = Date.parse(params[:from]).beginning_of_day rescue nil
      scope = scope.where('tickets.created_at >= ? OR tickets.close_at >= ?', from_date, from_date) if from_date
    end

    if params[:to].present?
      to_date = Date.parse(params[:to]).end_of_day rescue nil
      scope = scope.where('tickets.created_at <= ? OR tickets.close_at <= ?', to_date, to_date) if to_date
    end

    if params[:group_id].present?
      scope = scope.where(group_id: params[:group_id].to_i)
    end

    if params[:priority_id].present?
      scope = scope.where(priority_id: params[:priority_id].to_i)
    end

    scope
  end

  def format_duration(minutes)
    return '0 menit' if minutes.blank? || minutes.to_f <= 0

    mins = minutes.to_f.round
    return '< 1 menit' if mins.zero?

    days = mins / 1440
    hours = (mins % 1440) / 60
    rem_mins = mins % 60

    parts = []
    parts << "#{days} hari" if days > 0
    parts << "#{hours} jam" if hours > 0
    parts << "#{rem_mins} mnt" if rem_mins > 0 || parts.empty?
    parts.join(' ')
  end

  def authorize_staff!
    is_staff = current_user.roles.where(name: ['Admin', 'Agent']).any? ||
               (current_user.respond_to?(:permissions?) && (current_user.permissions?('ticket.agent') || current_user.permissions?('admin') || current_user.permissions?('report')))

    return if is_staff

    render json: { error: 'Akses ditolak. Fitur ini hanya untuk petugas support dan administrator.' }, status: :forbidden
  end
end
