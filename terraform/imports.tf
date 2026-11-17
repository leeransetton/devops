# These DNS zones already existed in DigitalOcean before OpenTofu managed them.
# Safe to delete this file after the first successful apply.
import {
  for_each = toset(["leeransetton.com", "sqloutputtojson.com", "gamadanak.com"])
  to       = digitalocean_domain.this[each.value]
  id       = each.value
}
