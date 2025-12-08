import Config

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

config :ex_aws, :dynamodb,
  scheme: "http://",
  host: "localhost",
  port: 4566,
  region: "us-east-1"

config :pizza,
  events_table: "pizza_events_test"
