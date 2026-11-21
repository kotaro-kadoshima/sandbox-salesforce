# SObject Reads MCP Server

The `platform/sobject-reads` server provides read-only access to standard and custom objects in your Salesforce org. It is the safest of the SObject server family: agents can discover schema, query records, search across objects, and traverse relationships — but cannot create, update, or delete anything. No data changes are possible through this server.

If you’re still evaluating how best to put AI to work in production, this is a great place to start. Read-only access is sufficient for answering questions, summarizing data, generating reports, preparing talking points before a meeting, and surfacing insights from Salesforce data. Limiting agents to read-only access also satisfies common enterprise requirements around human-in-the-loop review for any data modification. See [Best Practices](/docs/platform/hosted-mcp-servers/guide/general-best-practices.md) for guidance on access control and human-in-the-loop design.

When you’re ready to give agents write access, the other SObject servers are available: [SObject Mutations](/docs/platform/hosted-mcp-servers/references/reference/sobject-mutations.md) adds create and update, [SObject Deletes](/docs/platform/hosted-mcp-servers/references/reference/sobject-deletes.md) adds delete, and [SObject All](/docs/platform/hosted-mcp-servers/references/reference/sobject-all.md) provides the full range.

## Server URL

- Production: `https://api.salesforce.com/platform/mcp/v1/platform/sobject-reads`
- Sandbox/Scratch: `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`

## Example Prompts

- "What are the top 10 opportunities by amount currently in the pipeline?"
- "Give me a summary of all cases opened in the last 7 days for accounts in the Financial Services industry."
- "Find everything related to Acme Corp — contacts, opportunities, and open cases."
- "Who are the contacts at GlobalTech and what are their titles?"

## Available Tools

The `sobject-reads` server provides the following tools.

### `getObjectSchema`

Returns Salesforce schema information optimized for LLM consumption. Call with no parameters first to get a compact index of all queryable business objects. Then call with a specific object name to get field-level details before writing queries. Includes admin-authored guidance alongside the standard schema.

**Two modes:**

- **Index mode** (no parameters): Compact list of all business objects with descriptions and relationships
- **Detail mode** (with object name): Full field schema plus any contextual admin guidance

**Inputs:**

| Parameter     | Type   | Required | Description                                                           |
| ------------- | ------ | -------- | --------------------------------------------------------------------- |
| `object-name` | string | No       | API name of the object. Omit to get the compact index of all objects. |

**Outputs:** Index mode: compact list of queryable objects with descriptions. Detail mode: full field schema with types, required flags, picklist values, relationships, and any admin-authored guidance.

### `soqlQuery`

Executes a SOQL query to retrieve Salesforce records. This is the primary way to read data when you know which object and fields you need. SOQL syntax: `SELECT fields FROM Object WHERE conditions ORDER BY field LIMIT n`. Supports relationship queries to traverse lookups and subqueries for child records. Always include a WHERE clause and a LIMIT clause. For large objects, filter on indexed fields to avoid timeout errors.

**Example:** `SELECT Id, Name, StageName, Amount, CloseDate FROM Opportunity WHERE StageName != 'Closed Lost' ORDER BY Amount DESC LIMIT 10`

**Inputs:**

| Parameter | Type   | Required | Description               |
| --------- | ------ | -------- | ------------------------- |
| `query`   | string | Yes      | A valid SOQL query string |

**Outputs:** Array of matching records with the fields specified in the SELECT clause.

### `find`

Executes a text search across multiple Salesforce objects simultaneously. Use this instead of `soqlQuery` when searching for a term that could exist in multiple object types, or when you don't know which object contains the data.

**Example:** `FIND {Acme} IN NAME FIELDS RETURNING Account(Id, Name), Contact(Id, Name, Email)`

**Inputs:**

| Parameter | Type   | Required | Description                |
| --------- | ------ | -------- | -------------------------- |
| `search`  | string | Yes      | A valid SOSL search string |

**Outputs:** Search result groups by object type, each containing matched records with the requested fields.

### `getUserInfo`

Returns the currently authenticated user's identity and context — User ID, name, email, role, profile, manager, local time, and timezone. Call this when you need to personalize responses, filter queries to "my" records using the returned User ID, or apply the user's time and locale when interpreting date-based requests.

**Inputs:**

| Parameter | Type | Required | Description            |
| --------- | ---- | -------- | ---------------------- |
| *(none)*  | —    | —        | No parameters required |

**Outputs:** Identity object with user ID, full name, email, username, profile, role, manager, local time, and timezone.

### `listRecentSobjectRecords`

Returns records of a specific type that the user recently viewed or modified. Use this as a starting point when the user refers to "my accounts," "recent cases," or "that opportunity I was looking at" without providing specific IDs or names.

**Inputs:**

| Parameter      | Type   | Required | Description                                                     |
| -------------- | ------ | -------- | --------------------------------------------------------------- |
| `sobject-name` | string | Yes      | API name of the object (e.g., `Account`, `Case`, `Opportunity`) |

**Outputs:** Array of recently viewed records of the specified type, ordered by last viewed date.

### `getRelatedRecords`

Retrieves child records related to a parent record by traversing relationships. Use this instead of a separate SOQL query when you already have a record ID and need its related records — for example, all Contacts for an Account, or all Opportunity Line Items for an Opportunity.

**Inputs:**

| Parameter           | Type   | Required | Description                                                  |
| ------------------- | ------ | -------- | ------------------------------------------------------------ |
| `sobject-name`      | string | Yes      | API name of the parent object                                |
| `id`                | string | Yes      | Salesforce record ID of the parent record                    |
| `relationship-path` | string | Yes      | Relationship name (e.g., `Contacts`, `OpportunityLineItems`) |

**Outputs:** Array of related records via the specified relationship.