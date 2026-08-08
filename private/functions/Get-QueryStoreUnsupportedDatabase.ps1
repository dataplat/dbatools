function Get-QueryStoreUnsupportedDatabase {
    <#
    .SYNOPSIS
        Internal function. Returns the databases the Query Store commands have to skip on a given instance.

    .DESCRIPTION
        Query Store is never available on master or tempdb. SQL Server rejects the ALTER there with
        "Cannot perform action because Query Store cannot be enabled on system database master." and
        sys.database_query_store_options has no row for those databases on any version.

        model depends on the version. Before SQL Server 2022 the ALTER is accepted but
        sys.database_query_store_options stays empty and SMO reports nothing back, so there is no state to read
        or verify. From SQL Server 2022 (v16) on, Query Store is enabled on model by default, which is how newly
        created databases get it, and model reports its configuration like any other database.

        Even where model works it stays out of the automatic sweep, because -AllDatabases means the user
        databases and changing Query Store on model changes the default for every database created afterwards.
        It is honoured only when the caller names it explicitly.

        The Query Store commands used to append these names to -ExcludeDatabase unconditionally, and
        Get-DbaDatabase lets -ExcludeDatabase win over -Database, so an explicit -Database master produced no
        output, no warning and no error. Callers pass their -Database list in here so that a database the user
        named on purpose is reported rather than silently dropped.

    .PARAMETER SqlInstance
        The connected server object, used to decide whether model is supported.

    .PARAMETER Database
        The database names the caller was asked to work on. Any name in this list that has to be skipped gets a
        warning explaining why.

    .PARAMETER FunctionName
        The name of the calling command, so the warning is attributed to it instead of to this helper.

    .EXAMPLE
        PS C:\> Get-QueryStoreUnsupportedDatabase -SqlInstance $server -Database master, model

        Returns the names to exclude and warns that master cannot have Query Store enabled.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [object[]]$Database,
        [string]$FunctionName = (Get-PSCallStack)[1].Command
    )

    $unsupportedDatabase = @("master", "tempdb")

    if ($Database -notcontains "model" -or $SqlInstance.VersionMajor -lt 16) {
        $unsupportedDatabase += "model"
    }

    foreach ($unsupportedName in $unsupportedDatabase) {
        if ($Database -notcontains $unsupportedName) {
            continue
        }

        if ($unsupportedName -eq "model") {
            $warningMessage = "Query Store cannot be read on model before SQL Server 2022. Skipping model on $SqlInstance."
        } else {
            $warningMessage = "Query Store cannot be enabled on system database $unsupportedName. Skipping $unsupportedName on $SqlInstance."
        }

        $splatWarnUnsupported = @{
            Level        = "Warning"
            Message      = $warningMessage
            FunctionName = $FunctionName
            Target       = $SqlInstance
        }
        Write-Message @splatWarnUnsupported
    }

    $unsupportedDatabase
}
