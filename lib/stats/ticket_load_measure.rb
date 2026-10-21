# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats::TicketLoadMeasure

  def self.generate(_user)
    # Total tickets in the system as requested
    total_tickets = Ticket.count

    {
      used_for_average:  total_tickets,
      average_per_agent: total_tickets,
      percent:           100,
      state:             'supergood',
      own:               total_tickets,
      total:             total_tickets,
    }
  end

  def self.average_state(result, _user_id)
    result
  end

end
