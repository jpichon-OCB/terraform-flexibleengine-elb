resource "flexibleengine_lb_loadbalancer_v2" "loadbalancer" {
  name          = "elb-${var.loadbalancer_name}"
  vip_subnet_id = var.subnet_id
  vip_address   = var.vip_address
}

resource "flexibleengine_networking_floatingip_v2" "loadbalancer_eip" {
  count      = var.bind_eip && var.eip_addr == null ? 1 : 0
  pool       = "admin_external_net"
  port_id    = flexibleengine_lb_loadbalancer_v2.loadbalancer.vip_port_id
  depends_on = [flexibleengine_lb_loadbalancer_v2.loadbalancer]
}

resource "flexibleengine_networking_floatingip_associate_v2" "loadbalancer_eip_attach" {
  count       = var.bind_eip && var.eip_addr != null ? 1 : 0
  floating_ip = var.eip_addr
  port_id     = flexibleengine_lb_loadbalancer_v2.loadbalancer.vip_port_id
}

resource "flexibleengine_lb_certificate_v2" "cert" {
  count       = var.cert && var.certId == null ? 1 : 0
  name        = var.cert_name
  domain      = var.domain
  private_key = var.private_key
  certificate = var.certificate
}

resource "flexibleengine_lb_listener_v2" "listeners" {
  for_each = local.elb_listener_map

  name                      = each.value.name
  protocol                  = each.value.protocol
  protocol_port             = each.key
  loadbalancer_id           = flexibleengine_lb_loadbalancer_v2.loadbalancer.id
  default_tls_container_ref = var.cert && lookup(each.value, "hasCert", null) && var.certId == null ? element(flexibleengine_lb_certificate_v2.cert.*.id, 0) : var.cert && lookup(each.value, "hasCert", null) && var.certId != null ? var.certId : null
}

resource "flexibleengine_lb_pool_v2" "pools" {
  for_each        = local.elb_pool_map
  name            = each.value.name
  protocol        = each.value.protocol
  lb_method       = each.value.lb_method
  listener_id     = each.value.listener_port != null ? flexibleengine_lb_listener_v2.listeners[each.value.listener_port].id : null
  loadbalancer_id = each.value.listener_port == null ? flexibleengine_lb_loadbalancer_v2.loadbalancer.id : null
}

resource "flexibleengine_lb_member_v2" "members" {
  count         = length(var.backends)
  name          = "${flexibleengine_lb_pool_v2.pools[lookup(var.backends[count.index], "pool_index", count.index)].name}-${element(var.backends.*.name, count.index)}"
  address       = var.backends_addresses[var.backends[count.index].address_index]
  protocol_port = var.backends[count.index].port
  pool_id       = flexibleengine_lb_pool_v2.pools[lookup(var.backends[count.index], "pool_index", count.index)].id
  subnet_id     = var.backends[count.index].subnet_id
  depends_on    = [flexibleengine_lb_pool_v2.pools]
}

resource "flexibleengine_lb_monitor_v2" "monitor" {
  for_each    = local.elb_monitors_map
  name        = each.value.name
  pool_id     = flexibleengine_lb_pool_v2.pools[each.value.pool_name].id
  type        = each.value.protocol
  port        = each.value.port
  delay       = each.value.delay
  timeout     = each.value.timeout
  max_retries = each.value.max_retries
  depends_on  = [flexibleengine_lb_pool_v2.pools, flexibleengine_lb_member_v2.members]
}

resource "flexibleengine_lb_monitor_v2" "monitor_http" {
  for_each       = local.elb_monitorsHttp_map
  name           = each.value.name
  pool_id        = flexibleengine_lb_pool_v2.pools[each.value.pool_name].id
  type           = each.value.protocol
  port           = each.value.port
  delay          = each.value.delay
  timeout        = each.value.timeout
  max_retries    = each.value.max_retries
  url_path       = each.value.url_path
  http_method    = each.value.http_method
  expected_codes = each.value.expected_codes
  depends_on     = [flexibleengine_lb_pool_v2.pools, flexibleengine_lb_member_v2.members]
}

resource "flexibleengine_lb_whitelist_v2" "whitelists" {
  count            = length(var.listeners_whitelist)
  enable_whitelist = var.listeners_whitelist[count.index].enable_whitelist
  whitelist        = var.listeners_whitelist[count.index].whitelist
  listener_id      = flexibleengine_lb_listener_v2.listeners[lookup(var.listeners_whitelist[count.index], "listener_index", count.index)].id
}

# resource "flexibleengine_lb_l7policy_v2" "l7policies" {
#   count                = length(var.l7policies)
#   name                 = var.l7policies[count.index].name
#   action               = var.l7policies[count.index].action
#   description          = var.l7policies[count.index].description
#   position             = var.l7policies[count.index].position
#   listener_id          = flexibleengine_lb_listener_v2.listeners[lookup(var.l7policies[count.index], "listener_index", count.index)].id
#   redirect_listener_id = var.l7policies[count.index].redirect_listener_index != null ? flexibleengine_lb_listener_v2.listeners[lookup(var.l7policies[count.index], "redirect_listener_index", count.index)].id : null
#   redirect_pool_id     = var.l7policies[count.index].redirect_pool_index != null ? flexibleengine_lb_pool_v2.pools[lookup(var.l7policies[count.index], "redirect_pool_index", count.index)].id : null
# }

# resource "flexibleengine_lb_l7rule_v2" "l7rules" {
#   count        = length(var.l7policies_rules)
#   l7policy_id  = flexibleengine_lb_l7policy_v2.l7policies[lookup(var.l7policies_rules[count.index], "l7policy_index", count.index)].id
#   type         = var.l7policies_rules[count.index].type
#   compare_type = var.l7policies_rules[count.index].compare_type
#   value        = var.l7policies_rules[count.index].value
# }


locals {
  elb_listeners_keys  = [for listener in var.listeners : listener.port]
  elb_listener_values = [for listener in var.listeners : listener]
  elb_listener_map    = zipmap(local.elb_listeners_keys, local.elb_listener_values)

  elb_pool_keys   = [for pool in var.pools : pool.name]
  elb_pool_values = [for pool in var.pools : pool]
  elb_pool_map    = zipmap(local.elb_pool_keys, local.elb_pool_values)

  elb_monitors_keys   = var.monitors != [] ? [for monitor in var.monitors : monitor.name] : null
  elb_monitors_values = var.monitors != [] ? [for monitor in var.monitors : monitor] : null
  elb_monitors_map    = var.monitors != [] ? zipmap(local.elb_monitors_keys, local.elb_monitors_values) : null

  elb_monitorsHttp_keys   = var.monitorsHttp != [] ? [for monitorHttp in var.monitorsHttp : monitorHttp.name] : null
  elb_monitorsHttp_values = var.monitorsHttp != [] ? [for monitorHttp in var.monitorsHttp : monitorHttp] : null
  elb_monitorsHttp_map    = var.monitorsHttp != [] ? zipmap(local.elb_monitorsHttp_keys, local.elb_monitorsHttp_values) : null
}