# THQ API v1

Endpoint when deployed through Supabase Edge Functions:

`POST /functions/v1/thq-api`

Authentication uses the caller's existing Supabase bearer token. The gateway does not use a service-role client for normal requests; PostgreSQL permission/location checks remain authoritative.

Request:

```json
{
  "tenant_id": "<uuid>",
  "resource": "inventory-intelligence",
  "action": "get",
  "payload": {
    "location_id": null,
    "days": 30,
    "query": ""
  }
}
```

Response:

```json
{
  "success": true,
  "api_version": "v1",
  "resource": "inventory-intelligence",
  "action": "get",
  "data": []
}
```

## Resources in v1
- `contract`
- `sync`
- `attention`
- `inventory-intelligence`
- `customer-credit`
- `supplier-payables`
- `reorder-suggestions`
- `purchase-orders` (`list`, `detail`, `create`, `status`)
- `business-summary`
- `store-summary`

Core sale/purchase/return/payment mutation endpoints are deliberately not proxied in v4.8.0. They remain on the hardened v4.7 transaction RPCs until the API boundary has production evidence.
