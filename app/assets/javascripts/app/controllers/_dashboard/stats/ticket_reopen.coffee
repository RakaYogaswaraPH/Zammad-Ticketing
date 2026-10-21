# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats extends App.ControllerDashboardStatsBase
  render: (data = {}) ->
    # Ticket reopen widget is deprecated/removed by user request
    if @$('.ticket_reopen').length > 0
      @$('.ticket_reopen').remove()
    else
      @el.remove()

# Disabled / Removed:
# App.Config.set('ticket_reopen', { controller: Stats, permission: 'ticket.agent', prio: 600, className: 'ticket_reopen' }, 'Stats')
