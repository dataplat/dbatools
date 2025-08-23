function Get-DbaDbFileGrowth {
    <#
    .SYNOPSIS
        Retrieves database file auto-growth settings and maximum size limits

    .DESCRIPTION
        Retrieves auto-growth configuration for data and log files across SQL Server databases, including growth type (percentage or fixed MB), growth increment values, and maximum size limits. This function helps DBAs quickly identify databases with problematic growth settings like percentage-based growth on large files, unlimited growth configurations, or insufficient growth increments that could cause performance issues during auto-growth events.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for file growth settings. Accepts wildcards for pattern matching.
        Use this when you need to check growth configuration for specific databases instead of all databases on the instance.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input.
        Use this when you want to analyze file growth settings for databases already retrieved by another dbatools command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File, Log
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbFileGrowth

    .EXAMPLE
        PS C:\> Get-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012

        Gets all database file growths on sql2017, sql2016, sql2012

    .EXAMPLE
        PS C:\> Get-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012 -Database pubs

        Gets the database file growth info for pubs on sql2017, sql2016, sql2012

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database test | Get-DbaDbFileGrowth

        Gets the test database file growth information on sql2016
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound Database) -and -not (Test-Bound SqlInstance)) {
            Stop-Function -Message "You must specify SqlInstance when specifying Database"
            return
        }

        $dbs = Get-DbaDbFile @PSBoundParameters
        foreach ($db in $dbs) {
            $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, MaxSize, GrowthType, Growth, 'LogicalName as File', 'PhysicalName as FileName', State
        }
    }
}