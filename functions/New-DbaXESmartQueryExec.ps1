function New-DbaXESmartQueryExec {
 <#
    .SYNOPSIS
     This Response type executes a T-SQL command against a target database whenever an event is recorded.

    .DESCRIPTION
    This Response type executes a T-SQL command against a target database whenever an event is recorded.

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Database
    Specifies the name of the database that contains the target table.

    .PARAMETER Query
    The T-SQL command to execute. This string can contain placeholders for properties taken from the events.

    Placeholders are in the form {PropertyName}, where PropertyName is one of the fields or actions available in the Event object.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/New-DbaXESmartQueryExec
    https://github.com/spaghettidba/XESmartTarget/wiki

     .EXAMPLE
    $response = New-DbaXESmartQueryExec -SqlInstance sql2017 -Database dbadb -Query "update table set whatever = 1"
    Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response
    
    Executes a T-SQL command against dbadb on sql2017 whenever a deadlock event is recorded.
	
    .EXAMPLE
    $response = New-DbaXESmartQueryExec -SqlInstance sql2017 -Database dbadb -Query "update table set whatever = 1"
    $params = @{
        SmtpServer = "smtp.ad.local"
        To = "admin@ad.local"
        Sender = "reports@ad.local"
        Subject = "Query executed"
        Body = "Query executed at {collection_time}"
        Attachment = "batch_text"
        AttachmentFileName = "query.sql"
    }
    $emailresponse = New-DbaXESmartEmail @params
    Start-DbaXESmartTarget -SqlInstance sql2017 -Session querytracker -Responder $response, $emailresponse
    
    Executes a T-SQL command against dbadb on sql2017 whenever a querytracker event is recorded. Also sends an email.
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [string]$Query,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $execute = New-Object -TypeName XESmartTarget.Core.Responses.ExecuteTSQLResponse
            $execute.ServerName = $server.Name
            $execute.DatabaseName = $Database
            $execute.TSQL = $Query

            if ($SqlCredential) {
                $execute.UserName = $SqlCredential.UserName
                $execute.Password = $SqlCredential.GetNetworkCredential().Password
            }

            $execute
        }
    }
}