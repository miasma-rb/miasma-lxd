# Miasma LXD

LXD API plugin for the miasma cloud library

## Supported credential attributes:

Supported attributes used in the credentials section of API
configurations:

```ruby
Miasma.api(
  :type => :compute,
  :provider => :lxd,
  :credentials => {
    ...
  }
)
```

### Required attributes

* `api_endpoint` - LXD HTTPS endpoint (e.g. https://127.0.0.1:8443)
* `ssl_key` - Path to client SSL key
* `ssl_certificate` - Path to client SSL certificate

### Initial connection required attributes

* `name` - Name of this client (defaults to hostname)
* `password` - Shared password with LXD to establish trust

## Current support matrix

|Model         |Create|Read|Update|Delete|
|--------------|------|----|------|------|
|AutoScale     |      |    |      |      |
|BlockStorage  |      |    |      |      |
|Compute       |  X   | X  |  X   |  X   |
|DNS           |      |    |      |      |
|LoadBalancer  |      |    |      |      |
|Network       |      |    |      |      |
|Orchestration |      |    |      |      |
|Queues        |      |    |      |      |
|Storage       |      |    |      |      |

## Info
* Repository: https://github.com/miasma-rb/miasma-lxd
