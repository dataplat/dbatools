## Introduction

This doc is simply used for tracking the directories in the bin folder and what use they are mapped to (e.g. function, workflow, etc.)

### Directories

| Folder | Date Added | Date Removed | Purpose | Comments |
| ----------- | ----------- | ----------- | ----------------------- | --------------------------------- |
| [bcp](/src/bin/bcp) | 2018-01-15 | | Added via permission from MS | Not utilized by the module, initial (3e6ba3c) |
| [csv](/src/bin/csv) | 2018-11-21 | | `Import-DbaCsv` | Commit: 2ff3f09 |
| [datageneration](/src/bin/datageneration) | 2019-04-03 | | Data generation functions | 0493840 |
| [datamasking](/src/bin/datamasking) | 2018-12-12 | | Used by multiple commands: `*-DbaDbmasking*` `*-DbaDbPii*` and `*-DbaDataGenerator*` | initial (6d3f915) |
| [diagnosticquery](/src/bin/diagnosticquery) | 2017-04-29 | | Used by `*-DbaDiagnosticquery` commands | initial (125b4e4) |
| [libraries](/src/bin/libraries) | 2019-07-01 | | Multiple commands | initial (f38749d) |
| [net452](/src/bin/net452) | 2018-11-30 | | dbatools.dll .NET 4.5.2 library | initial (057cc6f) |
| [netcoreapp2.1](/src/bin/netcoreapp2.1) | 2018-11-30 | | dbatools.dll dotnet 2.1 library | initial (057cc6f) |
| [perfmontemplates](/src/bin/perfmontemplates) | 2018-01-13 | Used by `*-DbaPfDataCollectorSetTemplate` functions | initial (7d6b057) |
| [projects] | 2017-06-22 | 2021-01-02 | Source code for dbatools.dll library | Moved to a dedicated repository sqlcollaborative/dbatools-library |
| [randomizer](/src/bin/randomizer) | 2019-04-03 | | Used by `Get-DbaRandomizedDataset*` | Initial (0493840) |
| [smo](/src/bin/smo) | 2017-07-21 | | SMO library | Initial (466107c) |
| [sqlcmd](/src/bin/sqlcmd) | 2018-02-15 | Add via permission from MS. Used by `Invoke-DbaXEReplay` | initial (b5ade4b) |
| [third-party-licenses](/src/bin/third-party-licenses) | 2017-12-13 | License details for 3rd party libraries | initial (fc17603) |
| [XEtemplates](/src/bin/XEtemplates) | 2018-01-11 | | Utilized by `*-DbaXE*` commands | initial (795f1dc) |

### Files

| File | Date Added | Date Removed | Purpose | Comments |
| ----------- | ----------- | ----------- | ----------------------- | --------------------------------- |
| [PSScriptAnalzyerRules.ps1](PSScriptAnalzyerRules.ps1) | 2017-02-28 | | Used by VS Code workspace settings | Initial (0da7b4b) |
| [dbatools.dll] | 2017-11-14 | | Main library used by the module | Initial (8c565c8) |
| [dbatools-buildref-index.json](/src/bin/dbatools-buildref-index.json) | 2017-02-27 | | Contains build reference for SQL Server, utilized by various commands | Initial (66fc0c1) |
| [dbatools-sqlinstallationcomponents.json](/src/bin/dbatools-sqlinstallationcomponents.json) | 2019-04-18 | Used by `Install-DbaInstance` | Initial (b7763a0) |
| [library.ps1](/src/bin/library.ps1) | 2017-02-17 | | Used by import process for the module library | Initial (0979382) |
| [sp_SQLskills_ConvertTraceToEEs.sql](/src/bin/sp_SQLskills_ConvertTraceToEEs.sql) | 2018-01-09 | | Used by `ConvertTo-DbaXESession` | Initial (55dbcf0) |
| [stig.sql](/src/bin/stig.sql) | 2017-08-17 | | Used by `Get-DbauserPermission` | Initial (1f1c5af) |
| [typealiases.ps1](/src/bin/typealiases.ps1) | 2017-04-10 | | Used with module import process | Initial (c755f45) |
| [xetemplates-metadata.xml](/src/bin/xetemplates-metadata.xml) | 2018-01-11 | | Used by `*-DbaXESEssionTemplate` command | Initial (35aedf4) |
