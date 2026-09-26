function Test-DbaFeatureSupport {
    <#
    .SYNOPSIS
        Internal function. Tells whether the engine behind a connected server supports a named feature.

    .DESCRIPTION
        The single place that knows from which version on, and on which engines, a feature exists. Commands ask
        this function instead of comparing VersionMajor themselves. See #10600.

        Every feature has a separate answer per engine, because version numbers cannot be compared across engines:
        Azure SQL Database reports version 12.0 while SMO reads VersionMajor from @@MICROSOFTVERSION, which there
        is the build of the engine (18 in 2026). A VersionMajor comparison therefore lets Azure SQL Database pass
        or fail by accident. The rules here name the engine instead.

        - SqlServer: a [version] from which on the feature exists, compared with the full version of the server,
          or $false where the box product never has it.
        - AzureSqlDatabase and ManagedInstance: $true or $false. They are versionless services that always run
          the current engine.

        This answers only whether the engine can have the feature. Whether a given database can have it (master,
        tempdb) and whether it is switched on are separate questions for the caller.

        The connection a command uses for its work is also separate. Connect-DbaInstance -MinimumVersion stays
        where it is. This function reads the server object it is given and never connects.

        It throws instead of guessing: on a feature name it does not know, on a server object whose version or
        engine cannot be read, and on an engine it has no rule for. Reporting support on missing metadata is how
        a command ends up trying a feature the server does not have.

        The rules for Managed Instance come from the Microsoft documentation and are not tested against a real
        Managed Instance, because the lab has none.

    .PARAMETER Server
        The connected server object (Microsoft.SqlServer.Management.Smo.Server) of the command.

    .PARAMETER Feature
        The name of the feature. Unknown names throw.

    .EXAMPLE
        PS C:\> Test-DbaFeatureSupport -Server $server -Feature QueryStoreCustomCapturePolicy

        Returns $true on SQL Server 2019 and later, Azure SQL Database and Azure SQL Managed Instance.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [object]$Server,
        [Parameter(Mandatory)]
        [string]$Feature
    )

    # Query Store is several features: the options of SQL Server 2016, the wait statistics and plan limit of
    # SQL Server 2017, the custom capture policy of SQL Server 2019, and a readable Query Store on model from
    # SQL Server 2022 on. Azure SQL Database has no model a user can reach.
    $featureRule = @{
        QueryStore                    = @{
            SqlServer        = [version]"13.0"
            AzureSqlDatabase = $true
            ManagedInstance  = $true
        }
        QueryStoreWaitStats           = @{
            SqlServer        = [version]"14.0"
            AzureSqlDatabase = $true
            ManagedInstance  = $true
        }
        QueryStoreMaxPlansPerQuery    = @{
            SqlServer        = [version]"14.0"
            AzureSqlDatabase = $true
            ManagedInstance  = $true
        }
        QueryStoreCustomCapturePolicy = @{
            SqlServer        = [version]"15.0"
            AzureSqlDatabase = $true
            ManagedInstance  = $true
        }
        QueryStoreOnModel             = @{
            SqlServer        = [version]"16.0"
            AzureSqlDatabase = $false
            ManagedInstance  = $true
        }
    }

    if (-not $featureRule.ContainsKey($Feature)) {
        throw "Unknown feature $Feature. Known features are: $(($featureRule.Keys | Sort-Object) -join ", ")."
    }
    $rule = $featureRule[$Feature]

    # A name or a DbaInstanceParameter would have to be connected first, and connecting is the caller's job.
    if ($Server -is [string] -or $Server -is [Dataplat.Dbatools.Parameter.DbaInstanceParameter]) {
        throw "Test-DbaFeatureSupport needs a connected server object, not the name $Server."
    }

    $engineType = [string]$Server.DatabaseEngineType
    $engineEdition = [string]$Server.DatabaseEngineEdition
    if (-not $engineType -or $engineType -eq "Unknown" -or -not $engineEdition -or $engineEdition -eq "Unknown") {
        throw "Cannot read the engine of $Server (engine type [$engineType], edition [$engineEdition]), so support for $Feature cannot be decided."
    }

    if ($engineType -eq "SqlAzureDatabase" -and $engineEdition -eq "SqlDatabase") {
        $engine = "AzureSqlDatabase"
    } elseif ($engineType -eq "Standalone" -and $engineEdition -eq "SqlManagedInstance") {
        $engine = "ManagedInstance"
    } elseif ($engineType -eq "Standalone") {
        $engine = "SqlServer"
    } else {
        throw "There is no rule for $Feature on the engine of $Server (engine type [$engineType], edition [$engineEdition])."
    }

    $engineRule = $rule[$engine]
    if ($engineRule -is [bool]) {
        return $engineRule
    }

    $serverVersion = $Server.Version
    if ($serverVersion -isnot [version] -or $serverVersion.Major -le 0) {
        throw "Cannot read the version of $Server, so support for $Feature cannot be decided."
    }
    return ($serverVersion -ge $engineRule)
}
