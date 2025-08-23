function Get-DbaCmConnection {
    <#
    .SYNOPSIS
        Retrieves cached Windows Management and CIM connections used by dbatools commands

    .DESCRIPTION
        Shows which remote computer connections are currently cached by dbatools for Windows Management and CIM operations. This helps you understand what authentication contexts are active and troubleshoot connection issues when running dbatools commands against remote SQL Server instances. Cached connections are automatically created when you run dbatools commands that need to access Windows services, registry, or file system on remote servers.

    .PARAMETER ComputerName
        Filters cached connections by computer name or server name. Supports wildcards for pattern matching.
        Use this to check connections to specific SQL Server hosts or to search for connections matching a pattern like "sql*prod*".

    .PARAMETER UserName
        Filters cached connections by the username in the stored credentials. Supports wildcards for pattern matching.
        Use this to find connections using specific service accounts or domain credentials. Will not match connections using integrated Windows authentication.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCmConnection

    .EXAMPLE
        PS C:\> Get-DbaCmConnection

        List all cached connections.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection sql2014

        List the cached connection - if any - to the server sql2014.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection -UserName "*charles*"

        List all cached connection that use a username containing "charles" as default or override credentials.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline)]
        [Alias('Filter')]
        [String[]]$ComputerName = "*",
        [String]$UserName = "*",
        [switch]$EnableException
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }
    process {
        foreach ($name in $ComputerName) {
            Write-Message -Level VeryVerbose -Message "Processing search. ComputerName: '$name' | Username: '$UserName'"
            ([Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Values | Where-Object { ($_.ComputerName -like $name) -and ($_.Credentials.UserName -like $UserName) })
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Ending"
    }
}