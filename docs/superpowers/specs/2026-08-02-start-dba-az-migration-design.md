# Start-DbaAzMigration Design

## Purpose

`Start-DbaAzMigration` provides a focused migration path from a supported SQL Server source to an existing Azure SQL Database logical server. It exports each selected user database to a local BACPAC and imports that BACPAC as a new Azure SQL database.

The command is a public orchestrator over the existing `Export-DbaDacPackage` and `Publish-DbaDacPackage` commands. It does not provision Azure resources, migrate instance-level objects, or translate security principals.

## Scope

The first version:

- Migrates one, several, or all accessible user databases from one source instance to one Azure SQL destination.
- Preserves each source database name at the destination.
- Creates a missing destination database through DacFx BACPAC import.
- Skips an existing destination database by default.
- Drops and recreates an existing destination database only when `-Force` is supplied and `ShouldProcess` approves the operation.
- Deletes locally generated BACPAC files after each attempt by default.
- Preserves generated BACPAC files when `-KeepBacpac` is supplied.
- Returns one standard `MigrationObject` status per database.

The first version does not:

- Create subscriptions, resource groups, logical servers, firewall rules, private endpoints, databases, or other Azure control-plane resources before import.
- Migrate SQL Server logins, credentials, jobs, linked servers, server roles, configuration, or other instance-level objects.
- Convert login-mapped users into contained SQL or Microsoft Entra users.
- Rename databases during migration.
- Fan out one migration to multiple Azure destinations.
- Support Azure SQL Managed Instance as a special case; `Copy-DbaDatabase` remains the purpose-built path for Managed Instance migrations.

## Why a New Public Command

`Start-DbaMigration` assumes a SQL Server instance destination and coordinates many server-level copy commands. Adding an Azure mode to it would spread Azure compatibility branches across database, login, Agent, credential, linked-server, configuration, and other steps that Azure SQL Database does not expose.

A private helper or documentation-only recipe would not provide the discoverable, supported workflow requested by issue #6838. A narrow public command gives users one intentional entry point while keeping the existing migration command comprehensible.

## Dependencies

No new module, installer command, internal installer, or installation prompt is required.

The default paths in `Export-DbaDacPackage` and `Publish-DbaDacPackage` use the Microsoft DacFx assemblies already supplied through `dbatools.library`. `Start-DbaAzMigration` will not use `Az.Sql`, Azure CLI, or the separately installed `SqlPackage` executable at runtime.

If DacFx is unavailable, normal dbatools module loading or the delegated DAC commands will produce the existing actionable dependency error. The migration command will not attempt an interactive installation during an automation workflow.

Azure CLI is used only by the local integration-test setup to create and later remove an isolated Azure SQL logical server. It is not a product dependency.

## Public Interface

The command uses `SupportsShouldProcess` with medium confirm impact and exposes:

| Parameter | Type | Behavior |
| --- | --- | --- |
| `Source` | `DbaInstanceParameter` | Required source SQL Server or reusable connected server object. |
| `Destination` | `DbaInstanceParameter` | Required Azure SQL logical server or reusable connected server object. |
| `SourceSqlCredential` | `PSCredential` | Optional source credential passed to `Connect-DbaInstance`. |
| `DestinationSqlCredential` | `PSCredential` | Optional destination credential passed to `Connect-DbaInstance`. SQL authentication and connection-string-based Microsoft Entra service-principal authentication remain available through existing dbatools connection behavior. |
| `Database` | `object[]` | Optional source database allow-list. When omitted, all accessible user databases are selected. |
| `ExcludeDatabase` | `object[]` | Optional source database deny-list applied after `Database`. |
| `Path` | `string` | Directory for generated BACPAC files. Defaults to `Path.DbatoolsTemp`. |
| `ExportDacOption` | `object` | Optional `Microsoft.SqlServer.Dac.DacExportOptions` passed to BACPAC export. |
| `ImportDacOption` | `object` | Optional `Microsoft.SqlServer.Dac.DacImportOptions` passed to BACPAC import. This is the supported way to select Azure edition, service objective, maximum size, timeouts, and other DacFx import settings. |
| `Force` | `switch` | Allows an existing destination database to be dropped before import. |
| `KeepBacpac` | `switch` | Retains generated BACPAC files instead of deleting them during cleanup. |
| `EnableException` | `switch` | Enables catchable exceptions instead of friendly warnings and failed status objects. |

`Database` and `ExcludeDatabase` use the existing dbatools database-name matching conventions. System databases are never selected.

## Connection and Validation Flow

1. Validate that `Path` exists or can be created by the standard dbatools export-directory helper.
2. Validate the option object types before opening database connections.
3. Connect once to the source with `Connect-DbaInstance`.
4. Connect once to the destination with a `master` database context so DacFx can create target databases.
5. Require the destination engine edition to be Azure SQL Database. A hostname-only Azure check is insufficient because Managed Instance also uses Azure hostnames. The error directs Managed Instance users to `Copy-DbaDatabase`.
6. Enumerate accessible, online user databases from the source.
7. Apply the requested include and exclude filters and fail clearly when an explicitly requested database is missing or inaccessible.
8. Process databases sequentially. BACPAC export and import are resource-intensive, and parallel behavior is outside this version's scope.

The source and destination connections are reused for the complete command invocation. The destination connection string obtained from the connected server is passed to `Publish-DbaDacPackage`, preventing an unnecessary second authentication round trip.

## Per-Database Migration Flow

For every selected database:

1. Create a status object with source, destination, source name, destination name, type `Database`, timestamp, empty status, and empty notes.
2. Check the destination for a database with the same name.
3. When it exists without `-Force`, emit a `Skipped` status with `Already exists on destination` and continue.
4. When it exists with `-Force`, ask `ShouldProcess` to drop and recreate it. If approved, call `Remove-DbaDatabase` with exceptions enabled.
5. Ask `ShouldProcess` to migrate the database. Under `-WhatIf`, do not export, import, delete a destination, or create a package.
6. Call `Export-DbaDacPackage` for exactly one database with `-Type Bacpac`, the selected path, the optional export settings, and exceptions enabled.
7. Confirm that export returned one existing BACPAC path. Treat an empty result or missing file as a failed export.
8. Pipe or pass that path to `Publish-DbaDacPackage` with `-Type Bacpac`, the destination connection string, the same database name, the optional import settings, and exceptions enabled.
9. Confirm that publish returned one result for the target database.
10. Emit `Successful` when import completes.
11. When import fails after the target was absent or removed by `-Force`, remove any partially created Azure SQL database. Then emit `Failed` with the underlying error in friendly mode or rethrow through `Stop-Function` in exception mode.
12. In `finally`, delete the local BACPAC unless `-KeepBacpac` was supplied.

Cleanup operations use the already connected destination and tolerate a target that DacFx never created. Cleanup failure is reported without hiding the original migration failure.

## Output

Each attempted database produces a `PSCustomObject` with these properties:

- `SourceServer`
- `DestinationServer`
- `Name`
- `DestinationDatabase`
- `Type`
- `Status`
- `Notes`
- `DateTime`
- `BacpacPath`
- `Elapsed`

The object is sent through `Select-DefaultView` with the standard `MigrationObject` type name and the default columns `DateTime`, `SourceServer`, `DestinationServer`, `Name`, `Type`, `Status`, and `Notes`. `BacpacPath` remains populated only when a package was created; the file can still have been removed by default cleanup.

## Error Behavior

- Invalid parameter combinations, wrong DacFx option types, missing requested source databases, connection failures, and non-Azure destinations stop the command before any migration begins.
- An existing destination without `-Force` is a safe per-database skip, not an exception.
- Export or import failures are isolated to the current database in friendly mode so later selected databases can still run.
- `-EnableException` makes the first operational failure catchable and stops further processing.
- Error messages identify the database and whether export, import, forced replacement, or cleanup failed.
- The command never installs software or prompts for module installation.

## Security and Data Handling

BACPACs contain schema and table data and therefore can contain sensitive information. Temporary packages are deleted by default even after failures. Users who request `-KeepBacpac` accept responsibility for securing and deleting those artifacts.

Credentials and connection strings are never written to the pipeline, verbose stream, result object, or test output. The integration test constructs its service-principal credential from GitHub encrypted secrets without logging it.

## Test Strategy

### Command Tests

`tests/Start-DbaAzMigration.Tests.ps1` will contain:

- The required Pester 6 header and static command name.
- A parameter-surface assertion.
- Focused validation tests for wrong option types and a non-Azure destination.
- Behavioral tests for database selection, safe existing-target skip, `-Force`, package cleanup, package retention, status output, `WhatIf`, and friendly versus exception behavior where those behaviors can run against real boundaries.

Mocks may supplement validation tests but do not count as behavioral coverage.

### Real Azure SQL Boundary

The secret-bearing Linux GitHub Actions integration workflow will execute the real command against:

- A separately running SQL Server container as the source.
- `dbatoolstest.database.windows.net` as the Azure SQL destination.
- Existing `TENANTID`, `CLIENTID`, and `CLIENTSECRET` encrypted secrets for Microsoft Entra service-principal authentication.

The test will:

1. Fail immediately if the required Azure SQL credentials are absent.
2. Create a uniquely named source database and table with deterministic rows.
3. Invoke `Start-DbaAzMigration` for that database.
4. Verify a successful migration status.
5. Connect independently to the newly created Azure SQL database.
6. Verify the schema and row values.
7. Verify the generated local BACPAC was deleted by default.
8. Drop the Azure SQL database and source database in `finally` cleanup.

The positive test is not a skipped placeholder. Missing credentials or an unavailable Azure boundary fail the upstream secret-bearing workflow.

### Local Azure Verification

For local verification, Azure CLI will create an isolated logical server in the authorized `dbatools-ci` resource group with a random administrator password and a firewall rule limited to the caller's public IP. The test will migrate one small database, verify it independently, and then remove the entire logical server in cleanup. No persistent password or database is retained.

### Regression and Compatibility Verification

Verification includes:

- New command unit and integration tests under Pester 6.
- Existing `Export-DbaDacPackage`, `Publish-DbaDacPackage`, and `Start-DbaMigration` unit tests.
- ScriptAnalyzer/formatter checks for all changed PowerShell files.
- Module import and command registration checks.
- PowerShell 3 syntax review, including no `::new()` usage or unsupported language constructs.
- A diff audit confirming no unrelated `ci-cost-reduction` branch changes entered the isolated feature branch.

## Registration and Documentation

The public command is registered in both `dbatools.psd1` and `dbatools.psm1`. Comment-based help documents the database-only scope, dependency decision, BACPAC security implications, `-Force` behavior, Azure edition configuration through `ImportDacOption`, and the fact that the logical server must already exist.

The `.NOTES` author is `the dbatools team + Claude`, and `.OUTPUTS` lists the concrete migration status properties.

## Completion Criteria

The feature is complete when:

- The public command is implemented and registered.
- It needs no dependency beyond the existing dbatools runtime.
- A real local SQL Server database is imported as a newly created Azure SQL database.
- The independently queried Azure destination contains the expected schema and data.
- Existing-destination safety, forced replacement, cleanup, retained-package, output, and error behaviors are covered.
- Required focused and regression tests pass with zero failures.
- The local Azure resources created for verification are removed.
