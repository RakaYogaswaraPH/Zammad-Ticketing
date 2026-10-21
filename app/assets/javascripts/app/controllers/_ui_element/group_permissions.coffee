# coffeelint: disable=camel_case_classes
class App.UiElement.group_permissions extends Spine.Module
  @render: (attribute, params = {}) ->
    groupsRaw      = App.Group.search(sortBy: 'name')
    groups         = groupsRaw.filter (elem) -> elem.active
    groupsSelected = groups.filter (elem) -> params.group_ids && !_.isEmpty(params.group_ids[elem.id])

    item = $(App.view('generic/user_permission_group')(
      params:         params
      groupsSelected: groupsSelected
      groupAccesses:  App.Group.accesses()
    ))

    @renderNewGroupDropdown(item, groups)
    @attachGroupsEvents(item, groups)

    # check/uncheck group permissions (particular permissions vs. full)
    item.on('click', '.checkbox-replacement', (event) ->
      App.PermissionHelper.switchGroupPermission(event)
    )

    item

  @renderNewGroupDropdown: (item, allGroups) ->
    selectedGroupIds = item
      .find('tr[data-id]')
      .toArray()
      .map (elem) -> parseInt elem.dataset.id

    filteredGroupIds = allGroups
      .filter (elem) -> !_.include(selectedGroupIds, elem.id)
      .map    (elem) -> elem.id.toString()

    attribute = {
      value:      ''
      nulloption: true,
      null:       true,
      relation:   'Group',
      filter:     filteredGroupIds
    }

    element = App.UiElement.ApplicationTreeSelect.render(attribute)

    item.find('.js-groupListItemAddNew').html(element)
    element.find('.js-shadow').trigger('change')

  @attachGroupsEvents: (item, groups) ->
    item
      .on('click', '.js-remove', (e) => @onRemoveGroup(e, item, groups))
      .on('click', '.js-add', (e) => @onAddGroup(e, item, groups))

    # Auto-add row when user checks any permission box in the new item row (if group selected)
    item.on('change click', '.js-groupListNewItemRow .js-groupListItem', (e) =>
      newGroupId = parseInt(item.find('.js-shadow').val())
      if newGroupId
        dummyEvent = {
          stopPropagation: ->
          preventDefault: ->
          target: item.find('.js-add').get(0)
        }
        @onAddGroup(dummyEvent, item, groups)
    )

    # Auto-add row when user selects a group in dropdown (if any permission box already checked)
    item.on('change', '.js-groupListNewItemRow .js-shadow', (e) =>
      newGroupId = parseInt(item.find('.js-shadow').val())
      hasChecked = item.find('.js-groupListNewItemRow .js-groupListItem:checked').length > 0
      if newGroupId && hasChecked
        dummyEvent = {
          stopPropagation: ->
          preventDefault: ->
          target: item.find('.js-add').get(0)
        }
        @onAddGroup(dummyEvent, item, groups)
    )

    # Global capture listener on modal Submit button click to ensure pending group is added before formParam runs
    $(document).off('click.groupPermissionsAutoAdd').on('click.groupPermissionsAutoAdd', '.modal-footer .btn--primary, .modal .js-submit', (e) =>
      if item.is(':visible')
        newGroupId = parseInt(item.find('.js-shadow').val())
        if newGroupId
          dummyEvent = {
            stopPropagation: ->
            preventDefault: ->
            target: item.find('.js-add').get(0)
          }
          @onAddGroup(dummyEvent, item, groups)
    )

  @onRemoveGroup: (e, item, groups) ->
    e.stopPropagation()
    e.preventDefault()

    e.target
      .closest('tr')
      .remove()

    @renderNewGroupDropdown(item, groups)

  @onAddGroup: (e, item, groups) ->
    e.stopPropagation()
    e.preventDefault()

    newGroupId = parseInt(item.find('.js-shadow').val())

    $(e.target.closest('tr')).find('.js-input').toggleClass('has-error', !newGroupId)

    return if !newGroupId

    group      = _.find(groups, (elem) -> elem.id == newGroupId)
    shadowRow  = item.find('.js-groupListShadowItemRow')

    newRow = shadowRow
      .clone()
      .removeClass('hide js-groupListShadowItemRow')
      .attr('data-id', group.id)

    newRow.find('td:first-child').text(group.displayName())

    $(e.target.closest('tr'))
      .find('.js-groupListItem')
      .each((i, elem) ->
        isChecked = elem.checked
        value     = elem.value

        newRow
          .find(".js-groupListItem[value=#{value}]")
          .prop('checked', isChecked)
          .attr('name', "group_ids::#{newGroupId}")
      )
      .prop('checked', false)

    newRow.insertBefore(shadowRow)

    @renderNewGroupDropdown(item, groups)
