# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats::TicketInProcess

  def self.generate(_user)
    open_state_ids = Ticket::State.by_category_ids(:open)
    open_count = Ticket.where(state_id: open_state_ids).count
    total_tickets = Ticket.count
    percent = total_tickets.nonzero? ? ((open_count.to_f / total_tickets) * 100).round(1) : 0

    state = if open_count.zero?
              "supergood"
            elsif open_count <= 5
              "good"
            elsif open_count <= 15
              "ok"
            else
              "bad"
            end

    {
      used_for_average:  open_count,
      average_per_agent: open_count,
      state:             state,
      in_process:        open_count,
      percent:           open_count,
      open_count:        open_count,
      total:             total_tickets,
    }
  end

  def self.average_state(result, _user_id)
    result
  end

end
