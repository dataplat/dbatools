#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Invoke-DbaSqlQuery {
    <#
        .SYNOPSIS
            A command to run explicit T-SQL commands or files.

        .DESCRIPTION
            This function is a wrapper command around Invoke-SqlCmd2.
            It was designed to be more convenient to use in a pipeline and to behave in a way consistent with the rest of our functions.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

        .PARAMETER Database
        The database to select before running the query. This list is auto-populated from the server.

        .PARAMETER Query
            Specifies one or more queries to be run. The queries can be Transact-SQL, XQuery statements, or sqlcmd commands. Multiple queries in a single batch may be separated by a semicolon.

            Do not specify the sqlcmd GO separator. Escape any double quotation marks included in the string.

            Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

        .PARAMETER File
            Specifies the path to one or several files to be used as the query input to Invoke-Sqlcmd2. The file can contain Transact-SQL statements, XQuery statements, sqlcmd commands and scripting variables.

        .PARAMETER SqlObject
            Specify on or multiple SQL objects. Those will be converted to script and their scripts run on the target system(s).

        .PARAMETER As
            Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', and 'SingleValue'

            PSObject output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

        .PARAMETER SqlParameters
            Specifies a hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

        .PARAMETER AppendServerInstance
            If this switch is enabled, the SQL Server instance will be appended to PSObject and DataRow output.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Database, Query
            Author: Fred Winmann (@FredWeinmann)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Invoke-DbaSqlQuery

        .EXAMPLE
            Invoke-DbaSqlQuery -SqlInstance server\instance -Query 'SELECT foo FROM bar'

            Runs the sql query 'SELECT foo FROM bar' against the instance 'server\instance'

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance [SERVERNAME] -Group [GROUPNAME] | Invoke-DbaSqlQuery -Query 'SELECT foo FROM bar'

            Runs the sql query 'SELECT foo FROM bar' against all instances in the group [GROUPNAME] on the CMS [SERVERNAME]

        .EXAMPLE
            "server1", "server1\nordwind", "server2" | Invoke-DbaSqlQuery -File "C:\scripts\sql\rebuild.sql"

            Runs the sql commands stored in rebuild.sql against the instances "server1", "server1\nordwind" and "server2"
    #>
    [CmdletBinding(DefaultParameterSetName = "Query")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]
        $SqlInstance,

        [Alias("Credential")]
        [PsCredential]
        $SqlCredential,

        [object]$Database,

        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Query")]
        [string]
        $Query,

        [Parameter(Mandatory = $true, ParameterSetName = "File")]
        [object[]]
        $File,

        [Parameter(Mandatory = $true, ParameterSetName = "SMO")]
        [Microsoft.SqlServer.Management.Smo.SqlSmoObject[]]
        $SqlObject,

        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]
        $As = "DataRow",

        [System.Collections.IDictionary]
        $SqlParameters,

        [switch]
        $AppendServerInstance,

        [Alias('Silent')]
        [switch]
        $EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $splatInvokeSqlCmd2 = @{
            As = $As
        }

        if (Test-Bound -ParameterName "SqlParameters") {
            $splatInvokeSqlCmd2["SqlParameters"] = $SqlParameters
        }
        if (Test-Bound -ParameterName "AppendServerInstance") {
            $splatInvokeSqlCmd2["AppendServerInstance"] = $AppendServerInstance
        }
        if (Test-Bound -ParameterName "Query") {
            $splatInvokeSqlCmd2["Query"] = $Query
        }

        if (Test-Bound -ParameterName "File") {
            $files = @()
            $temporaryFiles = @()
            $temporaryFilesCount = 0
            $temporaryFilesPrefix = (97 .. 122 | Get-Random -Count 10 | ForEach-Object { [char]$_ }) -join ''

            foreach ($item in $File) {
                if ($null -eq $item) { continue }

                $type = $item.GetType().FullName

                switch ($type) {
                    "System.IO.DirectoryInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found!" -Category ObjectNotFound
                            return
                        }

                        $item.GetFiles() | Where-Object Extension -EQ ".sql" | ForEach-Object { $files += $_.FullName }
                    }
                    "System.IO.FileInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found!" -Category ObjectNotFound
                            return
                        }

                        $files += $item.FullName
                    }
                    "System.String" {
                        $uri = [uri]$item

                        switch -regex ($uri.Scheme) {
                            "http" {
                                $tempfile = "$env:TEMP\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                                try {
                                    Invoke-WebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    $files += $tempfile
                                    $temporaryFilesCount++
                                    $temporaryFiles += $tempfile
                                }
                                catch {
                                    Stop-Function -Message "Failed to download file $item" -ErrorRecord $_
                                    return
                                }
                            }
                            default {
                                try {
                                    $paths = Resolve-Path $item | Select-Object -ExpandProperty Path | Get-Item -ErrorAction Stop
                                }
                                catch {
                                    Stop-Function -Message "Failed to resolve path: $item" -ErrorRecord $_
                                    return
                                }

                                foreach ($path in $paths) {
                                    if (-not $path.PSIsContainer) {
                                        if (([uri]$path.FullName).Scheme -ne 'file') {
                                            Stop-Function -Message "Could not resolve path $path as filesystem object"
                                            return
                                        }
                                        $files += $path.FullName
                                    }
                                }
                            }
                        }
                    }
                    default {
                        Stop-Function -Message "Unkown input type: $type" -Category InvalidArgument
                        return
                    }
                }
            }
        }

        if (Test-Bound -ParameterName "SqlObject") {
            $files = @()
            $temporaryFiles = @()
            $temporaryFilesCount = 0
            $temporaryFilesPrefix = (97 .. 122 | Get-Random -Count 10 | ForEach-Object { [char]$_ }) -join ''

            foreach ($object in $SqlObject) {
                try { $code = Export-DbaScript -InputObject $object -Passthru -EnableException }
                catch {
                    Stop-Function -Message "Failed to generate script for object $object" -ErrorRecord $_
                    return
                }

                try {
                    $newfile = "$env:TEMP\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                    Set-Content -Value $code -Path $newfile -Force -ErrorAction Stop -Encoding UTF8
                    $files += $newfile
                    $temporaryFilesCount++
                    $temporaryFiles += $newfile
                }
                catch {
                    Stop-Function -Message "Failed to write sql script to temp" -ErrorRecord $_
                    return
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance." -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Executing Invoke-SqlCmd2 against $instance" -Target $instance
            $conncontext = $server.ConnectionContext
            try {
                if ($Database -and $conncontext.DatabaseName -ne $Database) {
                    $conncontext = $server.ConnectionContext.Copy()
                    $conncontext.DatabaseName = $Database
                }
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        Invoke-Sqlcmd2 -SQLConnection $conncontext.SqlConnectionObject @splatInvokeSqlCmd2 -InputFile $item
                    }
                }
                else { Invoke-Sqlcmd2 -SQLConnection $conncontext.SqlConnectionObject @splatInvokeSqlCmd2 }
            }
            catch {
                Stop-Function -Message "[$instance] Failed during execution" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }

    end {
        # Execute end even when interrupting, as only used for cleanup

        if ($temporaryFiles) {
            # Clean up temporary files that were downloaded
            foreach ($item in $temporaryFiles) {
                Remove-Item -Path $item -ErrorAction Ignore
            }
        }
        Test-DbaDeprecation -DeprecatedOn '1.0.0' -Alias Invoke-DbaSqlCmd
    }
}
