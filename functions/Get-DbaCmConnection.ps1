function Get-DbaCmConnection
{
    <#
        .SYNOPSIS
            Retrieves windows management connections from the cache
        
        .DESCRIPTION
            Retrieves windows management connections from the cache
        
        .PARAMETER ComputerName
            The computername to ComputerName for.
        
        .PARAMETER UserName
            Username on credentials to look for. Will not find connections using the default windows credentials.
        
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
        
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
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [Alias('Filter')]
        [String[]]
        $ComputerName = "*",
        
        [String]
        $UserName = "*",
        
        [switch]
        $Silent
    )
    
    Begin
    {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }
    Process
    {
        foreach ($name in $ComputerName)
        {
            Write-Message -Level VeryVerbose -Message "Processing search. ComputerName: '$name' | Username: '$UserName'"
            ([sqlcollective.dbatools.Connection.ConnectionHost]::Connections.Values | Where-Object { ($_.ComputerName -like $name) -and ($_.Credentials.UserName -like $UserName) })
        }
    }
    End
    {
        Write-Message -Level InternalComment -Message "Ending"
    }
}
