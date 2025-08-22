function New-DbaCustomError {
    <#
    .SYNOPSIS
        Creates custom error messages in SQL Server's sys.messages table for standardized application and stored procedure error handling

    .DESCRIPTION
        Creates custom error messages in SQL Server's sys.messages table using sp_addmessage, enabling standardized error handling across applications and stored procedures. This replaces the need to manually execute sp_addmessage for each custom message you want to define.

        Custom error messages are essential for application development and database maintenance workflows where you need consistent, meaningful error reporting. Instead of generic SQL Server errors, you can define specific messages like "Customer record not found" or "Data validation failed for field X" that make troubleshooting much easier for both developers and DBAs.

        You can assign custom message IDs between 50001 and 2147483647, set severity levels from 1-25, and optionally enable logging to both the Windows Application Log and SQL Server Error Log. The function supports multiple languages and can create messages across multiple SQL Server instances simultaneously.

        Note: When adding non-English messages, the U.S. English version must be created first with the same severity level. This command does not support Azure SQL Database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER MessageID
        An integer between 50001 and 2147483647.

    .PARAMETER Severity
        Severity level between 1 and 25.

    .PARAMETER MessageText
        Error message text with max length of 255 characters.

    .PARAMETER Language
        Language for this message. The valid values for Language are contained in the Name and Alias columns from sys.syslanguages.

    .PARAMETER WithLog
        Always write this message to the Windows application log and the SQL Server Error Log when it occurs.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, Error
        Author: Adam Lancaster, github.com/lancasteradam

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaCustomError

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance sqldev01, sqldev02 -MessageID 70001 -Severity 16 -MessageText "test"

        Creates a new custom message on the sqldev01 and sqldev02 instances with ID 70001, severity 16, and text "test".

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance sqldev01 -MessageID 70001 -Severity 16 -MessageText "test" -Language "French"

        Creates a new custom message on the sqldev01 instance for the french language with ID 70001, severity 16, and text "test".

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance sqldev01 -MessageID 70001 -Severity 16 -MessageText "test" -WithLog

        Creates a new custom message on the sqldev01 instance with ID 70001, severity 16, text "test", and enables the log mechanism.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance sqldev01
        PS C:\> $newMessage = New-DbaCustomError -SqlInstance $server -MessageID 70000 -Severity 16 -MessageText "test_70000"

        Creates a new custom message on the sqldev01 instance with ID 70000, severity 16, and text "test_70000"

        To modify the custom message at a later time the following can be done to change the severity from 16 to 20:

        PS C:\> $original = $server.UserDefinedMessages | Where-Object ID -eq 70000
        PS C:\> $messageID = $original.ID
        PS C:\> $severity = 20
        PS C:\> $text = $original.Text
        PS C:\> $language = $original.Language
        PS C:\> $removed = Remove-DbaCustomError -SqlInstance $server -MessageID 70000
        PS C:\> $alteredMessage = New-DbaCustomError -SqlInstance $server -MessageID $messageID -Severity $severity -MessageText $text -Language $language -WithLog

        The resulting updated message object is available in $alteredMessage.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateRange(50001, 2147483647)]
        [int32]$MessageID,
        [ValidateRange(1, 25)]
        [int32]$Severity,
        [ValidateLength(0, 255)]
        [String]$MessageText,
        [String]$Language = 'English',
        [switch]$WithLog,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $languageDetails = $server.Query("SELECT TOP 1 name, alias, msglangid FROM sys.syslanguages WHERE name = '$Language' OR alias = '$Language'")

            if (Test-Bound Language) {
                if ($null -eq $languageDetails) {
                    Stop-Function -Message "$instance does not have the $Language installed" -Target $instance -Continue
                }
            }

            $languageName = $languageDetails.name
            $languageAlias = $languageDetails.alias
            $langId = $languageDetails.msglangid

            if ($Pscmdlet.ShouldProcess($instance, "Creating new server message with id $MessageID on $instance")) {
                Write-Message -Level Verbose -Message "Creating new server message with id $MessageID on $instance"
                try {
                    $userDefinedMessage = New-Object -TypeName Microsoft.SqlServer.Management.Smo.UserDefinedMessage
                    $userDefinedMessage.Parent = $server
                    $userDefinedMessage.ID = $MessageID

                    if (Test-Bound Language) {
                        $userDefinedMessage.Language = $Language
                    } else {
                        $userDefinedMessage.Language = ($server.Query("SELECT syslang.name FROM sys.syslanguages syslang JOIN sys.configurations config ON syslang.langid = config.value_in_use AND config.name = 'default language'")).name
                    }

                    $userDefinedMessage.Severity = $Severity
                    $userDefinedMessage.Text = $MessageText

                    if (Test-Bound WithLog) {
                        $userDefinedMessage.IsLogged = $true
                    }

                    $userDefinedMessage.Create()

                    # return the new message object from the server to get all properties refreshed (the $userDefinedMessage.Refresh() method does not work as expected)
                    $server.UserDefinedMessages | Where-Object { $_.ID -eq $MessageID -and $_.Language -eq $userDefinedMessage.Language }
                } catch {
                    Stop-Function -Message "Error occurred while trying to create a message with id $MessageID on $instance" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}