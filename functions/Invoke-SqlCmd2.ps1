function Invoke-Sqlcmd2
{
    <#
    .SYNOPSIS
        Runs a T-SQL script.

    .DESCRIPTION
        Runs a T-SQL script. Invoke-Sqlcmd2 runs the whole scipt and only captures the first selected result set, such as the output of PRINT statements when -verbose parameter is specified.
        Paramaterized queries are supported.

        Help details below borrowed from Invoke-Sqlcmd

    .PARAMETER ServerInstance
        One or more ServerInstances to query. For default instances, only specify the computer name: "MyComputer". For named instances, use the format "ComputerName\InstanceName".

    .PARAMETER Database
        A character string specifying the name of a database. Invoke-Sqlcmd2 connects to this database in the instance that is specified in -ServerInstance.

        If a SQLConnection is provided, we explicitly switch to this database

    .PARAMETER Query
        Specifies one or more queries to be run. The queries can be Transact-SQL (? or XQuery statements, or sqlcmd commands. Multiple queries separated by a semicolon can be specified. Do not specify the sqlcmd GO separator. Escape any double quotation marks included in the string ?). Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

    .PARAMETER InputFile
        Specifies a file to be used as the query input to Invoke-Sqlcmd2. The file can contain Transact-SQL statements, (? XQuery statements, and sqlcmd commands and scripting variables ?). Specify the full path to the file.

    .PARAMETER Credential
        Specifies A PSCredential for SQL Server Authentication connection to an instance of the Database Engine.

        If -Credential is not specified, Invoke-Sqlcmd attempts a Windows Authentication connection using the Windows account running the PowerShell session.

        SECURITY NOTE: If you use the -Debug switch, the connectionstring including plain text password will be sent to the debug stream.

    .PARAMETER Encrypt
        If specified, will request that the connection to the SQL is done over SSL. This requires that the SQL Server has been set up to accept SSL requests. For information regarding setting up SSL on SQL Server, visit this link: https://technet.microsoft.com/en-us/library/ms189067(v=sql.105).aspx

    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.

    .PARAMETER ConnectionTimeout
        Specifies the number of seconds when Invoke-Sqlcmd2 times out if it cannot successfully connect to an instance of the Database Engine. The timeout value must be an integer between 0 and 65534. If 0 is specified, connection attempts do not time out.

    .PARAMETER As
        Specifies output type - DataSet, DataTable, array of DataRow, PSObject or Single Value

        PSObject output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

    .PARAMETER SqlParameters
        Hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

        Example:
            -Query "SELECT ServerName FROM tblServerInfo WHERE ServerName LIKE @ServerName"
            -SqlParameters @{"ServerName = "c-is-hyperv-1"}

    .PARAMETER AppendServerInstance
        If specified, append the server instance to PSObject and DataRow output

    .PARAMETER SQLConnection
        If specified, use an existing SQLConnection.
            We attempt to open this connection if it is closed

    .INPUTS
        None
            You cannot pipe objects to Invoke-Sqlcmd2

    .OUTPUTS
       As PSObject:     System.Management.Automation.PSCustomObject
       As DataRow:      System.Data.DataRow
       As DataTable:    System.Data.DataTable
       As DataSet:      System.Data.DataTableCollectionSystem.Data.DataSet
       As SingleValue:  Dependent on data type in first column.

    .EXAMPLE
        Invoke-Sqlcmd2 -ServerInstance "MyComputer\MyInstance" -Query "SELECT login_time AS 'StartTime' FROM sysprocesses WHERE spid = 1"

        This example connects to a named instance of the Database Engine on a computer and runs a basic T-SQL query.
        StartTime
        -----------
        2010-08-12 21:21:03.593

    .EXAMPLE
        Invoke-Sqlcmd2 -ServerInstance "MyComputer\MyInstance" -InputFile "C:\MyFolder\tsqlscript.sql" | Out-File -filePath "C:\MyFolder\tsqlscript.rpt"

        This example reads a file containing T-SQL statements, runs the file, and writes the output to another file.

    .EXAMPLE
        Invoke-Sqlcmd2  -ServerInstance "MyComputer\MyInstance" -Query "PRINT 'hello world'" -Verbose

        This example uses the PowerShell -Verbose parameter to return the message output of the PRINT command.
        VERBOSE: hello world

    .EXAMPLE
        Invoke-Sqlcmd2 -ServerInstance MyServer\MyInstance -Query "SELECT ServerName, VCNumCPU FROM tblServerInfo" -as PSObject | ?{$_.VCNumCPU -gt 8}
        Invoke-Sqlcmd2 -ServerInstance MyServer\MyInstance -Query "SELECT ServerName, VCNumCPU FROM tblServerInfo" -as PSObject | ?{$_.VCNumCPU}

        This example uses the PSObject output type to allow more flexibility when working with results.

        If we used DataRow rather than PSObject, we would see the following behavior:
            Each row where VCNumCPU does not exist would produce an error in the first example
            Results would include rows where VCNumCPU has DBNull value in the second example

    .EXAMPLE
        'Instance1', 'Server1/Instance1', 'Server2' | Invoke-Sqlcmd2 -query "Sp_databases" -as psobject -AppendServerInstance

        This example lists databases for each instance.  It includes a column for the ServerInstance in question.
            DATABASE_NAME          DATABASE_SIZE REMARKS        ServerInstance
            -------------          ------------- -------        --------------
            REDACTED                       88320                Instance1
            master                         17920                Instance1
            ...
            msdb                          618112                Server1/Instance1
            tempdb                        563200                Server1/Instance1
            ...
            OperationsManager           20480000                Server2

    .EXAMPLE
        #Construct a query using SQL parameters
            $Query = "SELECT ServerName, VCServerClass, VCServerContact FROM tblServerInfo WHERE VCServerContact LIKE @VCServerContact AND VCServerClass LIKE @VCServerClass"

        #Run the query, specifying values for SQL parameters
            Invoke-Sqlcmd2 -ServerInstance SomeServer\NamedInstance -Database ServerDB -query $query -SqlParameters @{ VCServerContact="%cookiemonster%"; VCServerClass="Prod" }

            ServerName    VCServerClass VCServerContact
            ----------    ------------- ---------------
            SomeServer1   Prod          cookiemonster, blah
            SomeServer2   Prod          cookiemonster
            SomeServer3   Prod          blah, cookiemonster

    .EXAMPLE
        Invoke-Sqlcmd2 -SQLConnection $Conn -Query "SELECT login_time AS 'StartTime' FROM sysprocesses WHERE spid = 1"

        This example uses an existing SQLConnection and runs a basic T-SQL query against it

        StartTime
        -----------
        2010-08-12 21:21:03.593

    .NOTES
        Changelog moved to CHANGELOG.md:
        
        https://github.com/sqlcollaborative/Invoke-SqlCmd2/blob/master/CHANGELOG.md

    .LINK
        https://github.com/sqlcollaborative/Invoke-SqlCmd2

    .LINK
        https://github.com/RamblingCookieMonster/PowerShell

    .LINK
        New-SQLConnection

    .FUNCTIONALITY
        SQL
    #>

    [CmdletBinding( DefaultParameterSetName='Ins-Que' )]
    [OutputType([System.Management.Automation.PSCustomObject],[System.Data.DataRow],[System.Data.DataTable],[System.Data.DataTableCollection],[System.Data.DataSet])]
    param(
        [Parameter( ParameterSetName='Ins-Que',
                    Position=0,
                    Mandatory=$true,
                    ValueFromPipeline=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false,
                    HelpMessage='SQL Server Instance required...' )]
        [Parameter( ParameterSetName='Ins-Fil',
                    Position=0,
                    Mandatory=$true,
                    ValueFromPipeline=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false,
                    HelpMessage='SQL Server Instance required...' )]
        [Alias( 'Instance', 'Instances', 'ComputerName', 'Server', 'Servers' )]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $ServerInstance,

        [Parameter( Position=1,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false)]
        [string]
        $Database,

        [Parameter( ParameterSetName='Ins-Que',
                    Position=2,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName='Con-Que',
                    Position=2,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [string]
        $Query,

        [Parameter( ParameterSetName='Ins-Fil',
                    Position=2,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName='Con-Fil',
                    Position=2,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [ValidateScript({ Test-Path $_ })]
        [string]
        $InputFile,

        [Parameter( ParameterSetName='Ins-Que',
                    Position=3,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false)]
        [Parameter( ParameterSetName='Ins-Fil',
                    Position=3,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false)]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter( ParameterSetName='Ins-Que',
                    Position=4,
                    Mandatory=$false,
                    ValueFromRemainingArguments=$false)]
        [Parameter( ParameterSetName='Ins-Fil',
                    Position=4,
                    Mandatory=$false,
                    ValueFromRemainingArguments=$false)]
        [switch]
        $Encrypt,

        [Parameter( Position=5,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Int32]
        $QueryTimeout=600,

        [Parameter( ParameterSetName='Ins-Fil',
                    Position=6,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName='Ins-Que',
                    Position=6,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Int32]
        $ConnectionTimeout=15,

        [Parameter( Position=7,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [ValidateSet("DataSet", "DataTable", "DataRow","PSObject","SingleValue")]
        [string]
        $As="DataRow",

        [Parameter( Position=8,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [System.Collections.IDictionary]
        $SqlParameters,

        [Parameter( Position=9,
                    Mandatory=$false )]
        [switch]
        $AppendServerInstance,

        [Parameter( ParameterSetName = 'Con-Que',
                    Position=10,
                    Mandatory=$false,
                    ValueFromPipeline=$false,
                    ValueFromPipelineByPropertyName=$false,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName = 'Con-Fil',
                    Position=10,
                    Mandatory=$false,
                    ValueFromPipeline=$false,
                    ValueFromPipelineByPropertyName=$false,
                    ValueFromRemainingArguments=$false )]
        [Alias( 'Connection', 'Conn' )]
        [ValidateNotNullOrEmpty()]
        [System.Data.SqlClient.SQLConnection]
        $SQLConnection
    )

    Begin
    {
        if ($InputFile)
        {
            $filePath = $(Resolve-Path $InputFile).path
            $Query =  [System.IO.File]::ReadAllText("$filePath")
        }

        Write-Verbose "Running Invoke-Sqlcmd2 with ParameterSet '$($PSCmdlet.ParameterSetName)'.  Performing query '$Query'"

        If($As -eq "PSObject")
        {
            #This code scrubs DBNulls.  Props to Dave Wyatt
            $cSharp = @'
                using System;
                using System.Data;
                using System.Management.Automation;

                public class DBNullScrubber
                {
                    public static PSObject DataRowToPSObject(DataRow row)
                    {
                        PSObject psObject = new PSObject();

                        if (row != null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
                        {
                            foreach (DataColumn column in row.Table.Columns)
                            {
                                Object value = null;
                                if (!row.IsNull(column))
                                {
                                    value = row[column];
                                }

                                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
                            }
                        }

                        return psObject;
                    }
                }
'@

            Try
            {
                Add-Type -TypeDefinition $cSharp -ReferencedAssemblies 'System.Data','System.Xml' -ErrorAction stop
            }
            Catch
            {
                If(-not $_.ToString() -like "*The type name 'DBNullScrubber' already exists*")
                {
                    Write-Warning "Could not load DBNullScrubber.  Defaulting to DataRow output: $_"
                    $As = "Datarow"
                }
            }
        }

        #Handle existing connections
        if($PSBoundParameters.ContainsKey('SQLConnection'))
        {
            if($SQLConnection.State -notlike "Open")
            {
                Try
                {
                    Write-Verbose "Opening connection from '$($SQLConnection.State)' state"
                    $SQLConnection.Open()
                }
                Catch
                {
                    Throw $_
                }
            }

            if($Database -and $SQLConnection.Database -notlike $Database)
            {
                Try
                {
                    Write-Verbose "Changing SQLConnection database from '$($SQLConnection.Database)' to $Database"
                    $SQLConnection.ChangeDatabase($Database)
                }
                Catch
                {
                    Throw "Could not change Connection database '$($SQLConnection.Database)' to $Database`: $_"
                }
            }

            if($SQLConnection.state -like "Open")
            {
                $ServerInstance = @($SQLConnection.DataSource)
            }
            else
            {
                Throw "SQLConnection is not open"
            }
        }

    }
    Process
    {
        foreach($SQLInstance in $ServerInstance)
        {
            Write-Verbose "Querying ServerInstance '$SQLInstance'"

            if($PSBoundParameters.Keys -contains "SQLConnection")
            {
                $Conn = $SQLConnection
            }
            else
            {
                if ($Credential)
                {
                    $ConnectionString = "Server={0};Database={1};User ID={2};Password=`"{3}`";Trusted_Connection=False;Connect Timeout={4};Encrypt={5}" -f $SQLInstance,$Database,$Credential.UserName,$Credential.GetNetworkCredential().Password,$ConnectionTimeout,$Encrypt
                }
                else
                {
                    $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2};Encrypt={3}" -f $SQLInstance,$Database,$ConnectionTimeout,$Encrypt
                }

                $conn = New-Object System.Data.SqlClient.SQLConnection
                $conn.ConnectionString = $ConnectionString
                Write-Debug "ConnectionString $ConnectionString"

                Try
                {
                    $conn.Open()
                }
                Catch
                {
                    Write-Error $_
                    continue
                }
            }

            #Following EventHandler is used for PRINT and RAISERROR T-SQL statements. Executed when -Verbose parameter specified by caller
            if ($PSBoundParameters.Verbose)
            {
                $conn.FireInfoMessageEventOnUserErrors=$false # Shiyang, $true will change the SQL exception to information
                $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] { Write-Verbose "$($_)" }
                $conn.add_InfoMessage($handler)
            }

            $cmd = New-Object system.Data.SqlClient.SqlCommand($Query,$conn)
            $cmd.CommandTimeout=$QueryTimeout

            if ($SqlParameters -ne $null)
            {
                $SqlParameters.GetEnumerator() |
                    ForEach-Object {
                        If ($_.Value -ne $null)
                        { $cmd.Parameters.AddWithValue($_.Key, $_.Value) }
                        Else
                        { $cmd.Parameters.AddWithValue($_.Key, [DBNull]::Value) }
                    } > $null
            }

            $ds = New-Object system.Data.DataSet
            $da = New-Object system.Data.SqlClient.SqlDataAdapter($cmd)

            Try
            {
                [void]$da.fill($ds)
            }
            Catch [System.Data.SqlClient.SqlException] # For SQL exception
            {
                $Err = $_

                Write-Verbose "Capture SQL Error"

                if ($PSBoundParameters.Verbose) {Write-Verbose "SQL Error:  $Err"} #Shiyang, add the verbose output of exception

                switch ($ErrorActionPreference.tostring())
                {
                    {'SilentlyContinue','Ignore' -contains $_} {}
                    'Stop' {     Throw $Err }
                    'Continue' { Throw $Err}
                    Default {    Throw $Err}
                }
            }
            Catch # For other exception
            {
                Write-Verbose "Capture Other Error"  

                $Err = $_

                if ($PSBoundParameters.Verbose) {Write-Verbose "Other Error:  $Err"} 

                switch ($ErrorActionPreference.tostring())
                {
                    {'SilentlyContinue','Ignore' -contains $_} {}
                    'Stop' {     Throw $Err}
                    'Continue' { Throw $Err}
                    Default {    Throw $Err}
                }
            }
            Finally
            {
                #Close the connection
                if(-not $PSBoundParameters.ContainsKey('SQLConnection'))
                {
                    $conn.Close()
                }               
            }

            if($AppendServerInstance)
            {
                #Basics from Chad Miller
                $Column =  New-Object Data.DataColumn
                $Column.ColumnName = "ServerInstance"
                $ds.Tables[0].Columns.Add($Column)
                Foreach($row in $ds.Tables[0])
                {
                    $row.ServerInstance = $SQLInstance
                }
            }

            switch ($As)
            {
                'DataSet'
                {
                    $ds
                }
                'DataTable'
                {
                    $ds.Tables
                }
                'DataRow'
                {
                    $ds.Tables[0]
                }
                'PSObject'
                {
                    #Scrub DBNulls - Provides convenient results you can use comparisons with
                    #Introduces overhead (e.g. ~2000 rows w/ ~80 columns went from .15 Seconds to .65 Seconds - depending on your data could be much more!)
                    foreach ($row in $ds.Tables[0].Rows)
                    {
                        [DBNullScrubber]::DataRowToPSObject($row)
                    }
                }
                'SingleValue'
                {
                    $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                }
            }
        }
    }
} #Invoke-Sqlcmd2
