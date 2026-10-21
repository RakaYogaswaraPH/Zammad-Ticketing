# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketOpenCountController < ApplicationController
  prepend_before_action :authentication_check

  # GET /api/v1/ticket_open_count
  # Returns real-time metrics for dashboard cards:
  # - Open tickets count
  # - Total tickets count
  # - Fastest & slowest SLA duration from closed tickets
  def index
    open_state_ids = Ticket::State.by_category_ids(:open)
    open_count = Ticket.where(state_id: open_state_ids).count
    total_count = Ticket.count

    # SLA Durations (Fastest & Slowest from closed tickets)
    closed_scope = Ticket.joins(:state).where(ticket_states: { name: 'closed' }).where.not(close_in_min: nil)
    raw_durations = closed_scope.pick(
      Arel.sql('MIN(tickets.close_in_min)'),
      Arel.sql('MAX(tickets.close_in_min)')
    )

    min_min = raw_durations && raw_durations[0] ? raw_durations[0].to_i : nil
    max_min = raw_durations && raw_durations[1] ? raw_durations[1].to_i : nil

    render json: {
      open_count: open_count,
      total_count: total_count,
      min_duration_min: min_min,
      max_duration_min: max_min,
      min_duration_human: format_duration(min_min),
      max_duration_human: format_duration(max_min)
    }, status: :ok
  end

  private

  def format_duration(minutes)
    return '-' if minutes.blank? || minutes.to_f < 0
    return '< 1 mnt' if minutes.to_f.zero?

    mins = minutes.to_f.round
    days = mins / 1440
    hours = (mins % 1440) / 60
    rem_mins = mins % 60

    parts = []
    parts << "#{days} hari" if days > 0
    parts << "#{hours} jam" if hours > 0
    parts << "#{rem_mins} mnt" if rem_mins > 0 || parts.empty?
    parts.join(' ')
  end
end
