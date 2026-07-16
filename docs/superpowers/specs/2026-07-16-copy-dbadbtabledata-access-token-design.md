# Copy-DbaDbTableData Access Token Preservation Design

## Goal

Allow `Copy-DbaDbTableData` to copy into Azure SQL Database when `-Destination` receives an SMO server object created by `Connect-DbaInstance` with an access token, including tokens obtained through MFA, without losing that authentication context when the bulk-copy connection is opened.

## Root Cause

`Connect-DbaInstance` recognizes an SMO server wrapped by `DbaInstanceParameter` and reuses it when the requested database context already matches. The failing authentication transition occurs later: `Copy-DbaDbTableData` creates `SqlBulkCopy` from `ConnectionContext.ConnectionString`. A connection string does not contain `SqlConnection.AccessToken`, so the new bulk-copy connection attempts to authenticate without the token supplied on the connected destination object.

The command requires a separate destination connection because source streaming and destination bulk insert can target the same server and cannot safely share one active connection. The fix must therefore preserve authentication while retaining a distinct bulk-copy connection.

## Design

- Continue resolving the destination through `Connect-DbaInstance -Database $DestinationDatabase` so string and credential inputs retain the database-scoping fix from issue #9186.
- Build the dedicated destination `SqlConnection` explicitly from the resolved destination connection string and destination database.
- When the resolved destination's `SqlConnectionObject` contains an access token, copy that token to the dedicated destination connection before opening it.
- Construct `SqlBulkCopy` from the opened dedicated `SqlConnection`, retaining the existing options, streaming, timeout, mapping, and row-count behavior.
- Close and dispose the dedicated destination connection in both success and error paths without disconnecting the caller's SMO server object.
- Do not add a public `DestinationAccessToken` parameter or change `Connect-DbaInstance`; the authenticated destination object remains the public mechanism for MFA and token-based use.

## Behavioral Coverage

Add a focused integration test that:

- uses a separately running SQL Server boundary as the source;
- obtains a real Azure SQL access token through the authenticated Azure session or the repository service principal;
- creates an SMO destination connection to `dbatoolstest.database.windows.net` database `test` with that token;
- creates unique source and destination tables, copies rows with `Copy-DbaDbTableData`, and asserts the returned row count and Azure destination data;
- removes all created tables in cleanup;
- fails when Azure credentials or the Azure SQL boundary are unavailable rather than skipping.

The GitHub Actions integration workflow will expose the existing `TENANTID`, `CLIENTID`, and `CLIENTSECRET` secrets to this test. Local red-green verification will use the current `az` login to obtain the Azure SQL token.

## Error Handling

Connection construction, opening, bulk copy, and cleanup remain inside the command's existing exception-handling boundary. Cleanup checks each disposable object before closing or disposing it so an earlier connection failure does not mask the original error.

## Compatibility

- Preserve PowerShell 3-compatible syntax and existing dbatools formatting conventions.
- Preserve SQL, Windows, and Entra connection-string authentication behavior when no access token is present.
- Preserve same-instance copies by keeping a separate destination connection.
- Preserve Azure SQL database scoping through the existing destination connection resolution.

## Non-Goals

- No changes to token acquisition or renewal in `Connect-DbaInstance`.
- No new public parameters.
- No in-process fake, fabricated SMO object, Pester mock, source-text assertion, or call-count assertion.
- No unrelated refactoring of `Copy-DbaDbTableData`.
