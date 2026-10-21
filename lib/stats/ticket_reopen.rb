# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats::TicketReopen

  def self.generate(_user)
    closed_state_ids = Ticket::State.by_category_ids(:closed)
    open_state_ids = Ticket::State.by_category_ids(:open)

    # Count all state transitions from closed to open across all tickets in history
    ticket_obj = History::Object.lookup(name: 'Ticket')
    history_reopens = if ticket_obj
                        History.where(
                          history_object_id: ticket_obj.id,
                          id_from: closed_state_ids,
                          id_to: open_state_ids
                        ).count
                      else
                        0
                      end

    store_reopens = StatsStore.where(key: 'ticket:reopen').count

    reopen_count = [history_reopens, store_reopens].max
    total_tickets = Ticket.count

    state = if reopen_count.zero?
              'supergood'
            elsif reopen_count <= 2
              'good'
            elsif reopen_count <= 5
              'ok'
            else
              'bad'
            end

    {
      used_for_average:  reopen_count,
      percent:           reopen_count,
      reopen_count:      reopen_count,
      average_per_agent: reopen_count,
      state:             state,
      count:             reopen_count,
      total:             total_tickets,
    }
  end

  def self.average_state(result, _user_id)
    result
  end

  def self.log(object, o_id, changes, updated_by_id)
    return if object != 'Ticket'

    ticket = Ticket.lookup(id: o_id)
    return if !ticket

    return if !changes['state_id']
    return if !changes['state_id'][0]

    state_before      = Ticket::State.lookup(id: changes['state_id'][0])
    state_type_before = Ticket::StateType.lookup(id: state_before.state_type_id)
    return if state_type_before.name != 'closed'

    state_now      = Ticket::State.lookup(id: changes['state_id'][1])
    state_type_now = Ticket::StateType.lookup(id: state_now.state_type_id)
    return if state_type_now.name == 'closed'

    StatsStore.create(
      stats_storable: ticket.owner || User.find_by(id: 1),
      key:            'ticket:reopen',
      data:           { ticket_id: ticket.id, reopened_by_id: updated_by_id },
      created_at:     Time.zone.now,
      created_by_id:  updated_by_id,
    )
  end

end
