# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats extends App.ControllerDashboardStatsBase
  render: (data = {}) ->
    if !data.StatsTicketEscalation
      data.StatsTicketEscalation =
        state: 'supergood'
        own: 'Belum Ada'
        total: 0
        total_ratings: 0
        average_rating: 0.0

    data.StatsTicketEscalation.description = __('Performa rating kepuasan pelanggan terhadap pelayanan Anda berdasarkan penilaian tiket.')

    content = App.view('dashboard/stats/ticket_escalation')(data)

    if @$('.ticket_escalation').length > 0
      @$('.ticket_escalation').html(content)
    else
      @el.append(content)

App.Config.set('ticket_escalation', { controller: Stats, permission: 'ticket.agent', prio: 200, className: 'ticket_escalation' }, 'Stats')
