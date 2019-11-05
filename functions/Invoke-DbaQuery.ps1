function Invoke-DbaQuery {
    <#
    .SYNOPSIS
        A command to run explicit T-SQL commands or files.

    .DESCRIPTION
        This function is a wrapper command around Invoke-DbaAsync, which in turn is based on Invoke-SqlCmd2.
        It was designed to be more convenient to use in a pipeline and to behave in a way consistent with the rest of our functions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        The database to select before running the query. This list is auto-populated from the server.

    .PARAMETER Query
        Specifies one or more queries to be run. The queries can be Transact-SQL, XQuery statements, or sqlcmd commands. Multiple queries in a single batch may be separated by a semicolon or a GO

        Escape any double quotation marks included in the string.

        Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.

    .PARAMETER File
        Specifies the path to one or several files to be used as the query input.

    .PARAMETER SqlObject
        Specify one or more SQL objects. Those will be converted to script and their scripts run on the target system(s).

    .PARAMETER As
        Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', and 'SingleValue'

        PSObject output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

    .PARAMETER SqlParameters
        Specifies a hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

    .PARAMETER AppendServerInstance
        If this switch is enabled, the SQL Server instance will be appended to PSObject and DataRow output.

    .PARAMETER MessagesToOutput
        Use this switch to have on the output stream messages too (e.g. PRINT statements). Output will hold the resultset too. See examples for detail

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ReadOnly
        Execute the query with ReadOnly application intent.

    .NOTES
        Tags: Database, Query
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaQuery

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance server\instance -Query 'SELECT foo FROM bar'

        Runs the sql query 'SELECT foo FROM bar' against the instance 'server\instance'

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance [SERVERNAME] -Group [GROUPNAME] | Invoke-DbaQuery -Query 'SELECT foo FROM bar'

        Runs the sql query 'SELECT foo FROM bar' against all instances in the group [GROUPNAME] on the CMS [SERVERNAME]

    .EXAMPLE
        PS C:\> "server1", "server1\nordwind", "server2" | Invoke-DbaQuery -File "C:\scripts\sql\rebuild.sql"

        Runs the sql commands stored in rebuild.sql against the instances "server1", "server1\nordwind" and "server2"

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance "server1", "server1\nordwind", "server2" | Invoke-DbaQuery -File "C:\scripts\sql\rebuild.sql"

        Runs the sql commands stored in rebuild.sql against all accessible databases of the instances "server1", "server1\nordwind" and "server2"

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance . -Query 'SELECT * FROM users WHERE Givenname = @name' -SqlParameters @{ Name = "Maria" }

        Executes a simple query against the users table using SQL Parameters.
        This avoids accidental SQL Injection and is the safest way to execute queries with dynamic content.
        Keep in mind the limitations inherent in parameters - it is quite impossible to use them for content references.
        While it is possible to parameterize a where condition, it is impossible to use this to select which columns to select.
        The inserted text will always be treated as string content, and not as a reference to any SQL entity (such as columns, tables or databases).
    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance aglistener1 -ReadOnly -Query "select something from readonlydb.dbo.atable"

        Executes a query with ReadOnly application intent on aglistener1.
    #>
    [CmdletBinding(DefaultParameterSetName = "Query")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PsCredential]$SqlCredential,
        [string]$Database,
        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]$Query,
        [Int32]$QueryTimeout = 600,
        [Parameter(Mandatory, ParameterSetName = "File")]
        [Alias("InputFile")]
        [object[]]$File,
        [Parameter(Mandatory, ParameterSetName = "SMO")]
        [Microsoft.SqlServer.Management.Smo.SqlSmoObject[]]$SqlObject,
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]$As = "DataRow",
        [System.Collections.IDictionary]$SqlParameters,
        [switch]$AppendServerInstance,
        [switch]$MessagesToOutput,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$ReadOnly,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $splatInvokeDbaSqlAsync = @{
            As = $As
        }

        if (Test-Bound -ParameterName "SqlParameters") {
            $splatInvokeDbaSqlAsync["SqlParameters"] = $SqlParameters
        }
        if (Test-Bound -ParameterName "AppendServerInstance") {
            $splatInvokeDbaSqlAsync["AppendServerInstance"] = $AppendServerInstance
        }
        if (Test-Bound -ParameterName "Query") {
            $splatInvokeDbaSqlAsync["Query"] = $Query
        }
        if (Test-Bound -ParameterName "QueryTimeout") {
            $splatInvokeDbaSqlAsync["QueryTimeout"] = $QueryTimeout
        }
        if (Test-Bound -ParameterName "MessagesToOutput") {
            $splatInvokeDbaSqlAsync["MessagesToOutput"] = $MessagesToOutput
        }
        if (Test-Bound -ParameterName "Verbose") {
            $splatInvokeDbaSqlAsync["Verbose"] = $Verbose
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
                            Stop-Function -Message "Directory not found" -Category ObjectNotFound
                            return
                        }
                        $files += ($item.GetFiles() | Where-Object Extension -EQ ".sql").FullName

                    }
                    "System.IO.FileInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found." -Category ObjectNotFound
                            return
                        }

                        $files += $item.FullName
                    }
                    "System.String" {
                        if (Test-PsVersion -Is 3) {
                            $uri = [uri]$item
                        } else {
                            $uri = [uri]::New($item)
                        }

                        switch -regex ($uri.Scheme) {
                            "http" {
                                $tempfile = "$(Get-DbatoolsPath -Name temp)\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                                try {
                                    try {
                                        Invoke-TlsWebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    } catch {
                                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                                        Invoke-TlsWebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    }
                                    $files += $tempfile
                                    $temporaryFilesCount++
                                    $temporaryFiles += $tempfile
                                } catch {
                                    Stop-Function -Message "Failed to download file $item" -ErrorRecord $_
                                    return
                                }
                            }
                            default {
                                try {
                                    $paths = Resolve-Path $item | Select-Object -ExpandProperty Path | Get-Item -ErrorAction Stop
                                } catch {
                                    Stop-Function -Message "Failed to resolve path: $item" -ErrorRecord $_
                                    return
                                }

                                foreach ($path in $paths) {
                                    if (-not $path.PSIsContainer) {
                                        if (Test-PsVersion -Is 3) {
                                            if (([uri]$path.FullName).Scheme -ne 'file') {
                                                Stop-Function -Message "Could not resolve path $path as filesystem object"
                                                return
                                            }
                                        } else {
                                            if ([uri]::New($path).Scheme -ne 'file') {
                                                Stop-Function -Message "Could not resolve path $path as filesystem object"
                                                return
                                            }
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
                    $newfile = "$(Get-DbatoolsPath -Name temp)\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                    Set-Content -Value $code -Path $newfile -Force -ErrorAction Stop -Encoding UTF8
                    $files += $newfile
                    $temporaryFilesCount++
                    $temporaryFiles += $newfile
                } catch {
                    Stop-Function -Message "Failed to write sql script to temp" -ErrorRecord $_
                    return
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        if (Test-Bound -ParameterName "Database", "InputObject" -And) {
            Stop-Function -Category InvalidArgument -Message "You can't use -Database with piped databases"
            return
        }
        if (Test-Bound -ParameterName "SqlInstance", "InputObject" -And) {
            Stop-Function -Category InvalidArgument -Message "You can't use -SqlInstance with piped databases"
            return
        }
        if (Test-Bound -ParameterName "SqlInstance", "InputObject" -Not) {
            Stop-Function -Category InvalidArgument -Message "Please provide either SqlInstance or InputObject"
            return
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }
            $server = $db.Parent
            $conncontext = $server.ConnectionContext
            if ($conncontext.DatabaseName -ne $db.Name) {
                #$conncontext = $server.ConnectionContext.Copy()
                #$conncontext.DatabaseName = $db.Name
                $conncontext = $server.ConnectionContext.Copy().GetDatabaseConnection($db.Name)
            }
            try {
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        if ($null -eq $item) { continue }
                        $filePath = $(Resolve-Path -LiteralPath $item).ProviderPath
                        $QueryfromFile = [System.IO.File]::ReadAllText("$filePath")
                        Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync -Query $QueryfromFile
                    }
                } else { Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync }
            } catch {
                Stop-Function -Message "[$db] Failed during execution" -ErrorRecord $_ -Target $server -Continue
            }
        }
        foreach ($instance in $SqlInstance) {
            try {
                $connDbaInstanceParams = @{
                    SqlInstance   = $instance
                    SqlCredential = $SqlCredential
                    Database      = $Database
                }
                if ($ReadOnly) {
                    $connDbaInstanceParams.ApplicationIntent = "ReadOnly"
                }
                $server = Connect-DbaInstance @connDbaInstanceParams
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }
            $conncontext = $server.ConnectionContext
            try {
                if ($Database -and $conncontext.DatabaseName -ne $Database) {
                    #$conncontext = $server.ConnectionContext.Copy()
                    #$conncontext.DatabaseName = $Database
                    $conncontext = $server.ConnectionContext.Copy().GetDatabaseConnection($Database)
                }
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        if ($null -eq $item) { continue }
                        $filePath = $(Resolve-Path -LiteralPath $item).ProviderPath
                        $QueryfromFile = [System.IO.File]::ReadAllText("$filePath")
                        Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync -Query $QueryfromFile
                    }
                } else {
                    Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync
                }
            } catch {
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
    }
}
