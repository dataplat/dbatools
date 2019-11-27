function Get-DbaCmConnection {
    <#
    .SYNOPSIS
        Retrieves windows management connections from the cache

    .DESCRIPTION
        Retrieves windows management connections from the cache

    .PARAMETER ComputerName
        The computername to ComputerName for.

    .PARAMETER UserName
        Username on credentials to look for. Will not find connections using the default windows credentials.

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
            ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections.Values | Where-Object { ($_.ComputerName -like $name) -and ($_.Credentials.UserName -like $UserName) })
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Ending"
    }
}