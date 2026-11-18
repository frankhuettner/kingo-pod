# Langflow here: facts

- `GET $LANGFLOW_BASE_URL/api/v1/version` gives the version of this Langflow. `GET $LANGFLOW_BASE_URL/openapi.json`
  describes most of its API.
- `POST /api/v1/run/<flow id>` runs a flow and answers once, when the flow is done.
- `GET /api/v1/build/<job id>/events` is a stream: it does not end by itself.
