# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/sla_reports/summary',               to: 'sla_reports#summary', via: :get
  match api_path + '/sla_reports/chart_data',            to: 'sla_reports#chart_data', via: :get
  match api_path + '/sla_reports/tickets',               to: 'sla_reports#tickets', via: :get
  match api_path + '/sla_reports/filters_meta',          to: 'sla_reports#filters_meta', via: :get
  match api_path + '/sla_reports/ticket_sla/:id',        to: 'sla_reports#ticket_sla', via: :get
end

