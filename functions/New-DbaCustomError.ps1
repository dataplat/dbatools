function New-DbaCustomError {
    <#
    .SYNOPSIS
        Creates or replaces a user defined message in sys.messages. This command does not support Azure SQL Database.

    .DESCRIPTION
        This command provides a wrapper for the sp_addmessage system procedure that allows for user defined messages to be added to sys.messages.
        As noted in https://docs.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-addmessage-transact-sql?view=sql-server-ver15#remarks the english message must be present before the non-english messages can be added.

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

    .PARAMETER Replace
        Replace the message text and severity for an existing user defined message.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Configure, CustomError, Error, Logging, Messages, SystemDatabase
        Author: Adam Lancaster https://github.com/lancasteradam

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaCustomError

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance localhost, serverName2 -MessageID 70001 -Severity 16 -MessageText "test"

        Creates a new custom message on the localhost and serverName2 instances with ID 70001, severity 16, and text "test".

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance localhost -MessageID 70001 -Severity 16 -MessageText "test" -Language "French"

        Creates a new custom message on the localhost instance for the french language with ID 70001, severity 16, and text "test".

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance localhost -MessageID 70001 -Severity 20 -MessageText "test2" -Replace

        Replaces the text and severity on the localhost instance for the message with ID 70001.

    .EXAMPLE
        PS C:\> New-DbaCustomError -SqlInstance localhost -MessageID 70001 -Severity 16 -MessageText "test" -WithLog

        Creates a new custom message on the localhost instance with ID 70001, severity 16, text "test", and enables the log mechanism.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance localhost
        PS C:\> $newMessage = New-DbaCustomError -SqlInstance $server -MessageID 70000 -Severity 1 -MessageText "test_70000"
        PS C:\> $original = $server.UserDefinedMessages | Where-Object ID -eq 70000
        PS C:\> $messageID = $original.ID
        PS C:\> $severity = $original.Severity
        PS C:\> $text = $original.Text
        PS C:\> $language = $original.Language
        PS C:\> $removed = Remove-DbaCustomError -SqlInstance $server -MessageID 70000
        PS C:\> $alteredMessage = New-DbaCustomError -SqlInstance $server -MessageID $messageID -Severity $severity -MessageText $text -Language $language -WithLog

        Simulates the sp_altermessage procedure which only allows the log behavior of the message to be changed.
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
        [switch]$Replace,
        [switch]$EnableException
    )

    process {
        $newMessages = @()

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $languageDetails = $server.Query("SELECT TOP 1 name, alias, msglangid FROM sys.syslanguages WHERE name = '$Language' OR alias = '$Language'")

            if (Test-Bound Language) {
                if ($null -eq $languageDetails) {
                    Stop-Function -Message "$server does not have the $Language installed" -Target $instance -Continue
                }
            }

            $languageName = $languageDetails.name
            $languageAlias = $languageDetails.alias
            $langId = $languageDetails.msglangid

            if ($Pscmdlet.ShouldProcess("Creating new server message with id $MessageID on $server")) {
                Write-Message -Level Verbose -Message "Creating new server message with id $MessageID on $server"
                try {
                    if (Test-Bound Replace) {
                        $userDefinedMessage = $server.UserDefinedMessages | Where-Object { $_.ID -eq $MessageID -and ($_.Language -in $languageName, $languageAlias -or $_.LanguageID -eq $langId) } # special case for English and British English requires using the langId
                        $userDefinedMessage.Text = $MessageText
                        $userDefinedMessage.Severity = $Severity
                        $userDefinedMessage.Alter()
                        $newMessages += $userDefinedMessage
                    } else {
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

                        # pull the new message object from the server to get all properties refreshed (the $userDefinedMessage.Refresh() method does not work as expected)
                        $newMessages += $server.UserDefinedMessages | Where-Object { $_.ID -eq $MessageID -and $_.Language -eq $userDefinedMessage.Language }
                    }
                } catch {
                    Stop-Function -Message "Error occurred while trying to create a message with id $MessageID on $server" -ErrorRecord $_ -Continue
                }
            }
        }

        $newMessages
    }
}