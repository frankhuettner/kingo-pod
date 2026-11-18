# n8n here: facts

- The version of this n8n is in `../compose.yml` (`image: n8nio/n8n:…`). `GET $N8N_BASE_URL/api/v1/openapi.yml`
  describes its API.
- In the editor, saving does not change what runs; **Publish** does. Through the API, `PUT` on a published workflow
  publishes the change at once.
- The API has no route that starts a workflow. A workflow with a webhook runs when its webhook is called. Any other
  workflow runs when the student clicks **Execute workflow**.
