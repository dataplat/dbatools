function New-DbaSqlDirectory {
    <#
        .SYNOPSIS
            Creates new path as specified by the path variable

        .DESCRIPTION
            Uses master.dbo.xp_create_subdir to create the path
            Returns $true if the path can be created, $false otherwise

        .PARAMETER SqlInstance
            The SQL Server you want to run the test on.

        .PARAMETER Path
            The Path to tests. Can be a file or directory.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Path, Directory, Folder
            Author: Stuart Moore

            Requires: Admin access to server (not SQL Services),
            Remoting must be enabled and accessible if $SqlInstance is not local

            dbatools PowerShell module (https://dbatools.io)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/New-DbaSqlDirectory

        .EXAMPLE
            New-DbaSqlDirectory -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP

            If the SQL Server instance sqlcluster can create the path L:\MSAS12.MSSQLSERVER\OLAP it will do and return $true, if not it will return $false.

        .EXAMPLE
            $credential = Get-Credential
            New-DbaSqlDirectory -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP

            If the SQL Server instance sqlcluster can create the path L:\MSAS12.MSSQLSERVER\OLAP it will do and return $true, if not it will return $false. Uses a SqlCredential to connect
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    
    foreach ($instance in $SqlInstance) {
        try {
            Write-Message -Level Verbose -Message "Connecting to $instance."
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }
        
        $Path = $Path.Replace("'", "''")
        
        $exists = Test-DbaSqlPath -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Path $Path
        
        if ($exists) {
            Stop-Function -Message "$Path already exists" -Target $server -Continue
        }
        
        $sql = "EXEC master.dbo.xp_create_subdir'$path'"
        Write-Message -Level Debug -Message $sql
        
        try {
            $query = $server.Query($sql)
            $Created = $true
        }
        catch {
            $Created = $false
            Stop-Function -Message "Failure" -ErrorRecord $_
        }
        
        [pscustomobject]@{
            Server  = $SqlInstance
            Path    = $Path
            Created = $Created
        }
    }
}