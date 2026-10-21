# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats extends App.ControllerDashboardStatsBase
  render: (data = {}) ->
    # Channel distribution widget is deprecated/removed by user request
    if @$('.ticket_channel_distribution').length > 0
      @$('.ticket_channel_distribution').remove()
    else
      @el.remove()

# Disabled / Removed:
# App.Config.set('ticket_channel_distribution', { controller: Stats, permission: 'ticket.agent', prio: 300, className: 'ticket_channel_distribution' }, 'Stats')
