function Remove-DbaCustomError {
    <#
    .SYNOPSIS
        Removes user-defined error messages from the sys.messages system catalog

    .DESCRIPTION
        Removes custom error messages that applications have added to SQL Server's sys.messages catalog, cleaning up obsolete or unwanted user-defined messages with IDs between 50001 and 2147483647. This is essential when decommissioning applications, cleaning up test environments, or managing custom error message lifecycles during application deployments. You can remove messages for specific languages or all language versions of a message ID at once.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER MessageID
        Specifies the custom error message ID to remove from the sys.messages catalog.
        Must be between 50001 and 2147483647, which is the valid range for user-defined error messages.
        Use this to target specific custom errors that applications have registered with SQL Server.

    .PARAMETER Language
        Specifies which language version of the custom error message to remove.
        Accepts language names or aliases from sys.syslanguages (like 'English', 'French', 'Deutsch').
        Use 'All' to remove all language versions of the message ID at once. Defaults to 'English'.

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
        https://dbatools.io/Remove-DbaCustomError

    .EXAMPLE
        PS C:\> Remove-DbaCustomError -SqlInstance sqldev01, sqldev02 -MessageID 70001 -Language "French"

        Removes the custom message on the sqldev01 and sqldev02 instances with ID 70001 and language French.

    .EXAMPLE
        PS C:\> Remove-DbaCustomError -SqlInstance sqldev01, sqldev02 -MessageID 70001 -Language "All"

        Removes all custom messages on the sqldev01 and sqldev02 instances with ID 70001.

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
        [String]$Language = 'English',
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Language -ine "All") {
                $languageDetails = $server.Query("SELECT TOP 1 name, alias, msglangid FROM sys.syslanguages WHERE name = '$Language' OR alias = '$Language'")

                if ((Test-Bound Language) -and $null -eq $languageDetails) {
                    Stop-Function -Message "$instance does not have the $Language installed" -Target $instance -Continue
                }

                $languageName = $languageDetails.name
                $languageAlias = $languageDetails.alias
                $langId = $languageDetails.msglangid
            }

            if ($Pscmdlet.ShouldProcess($instance, "Removing server message with id $MessageID from $instance")) {
                Write-Message -Level Verbose -Message "Removing server message with id $MessageID and language $Language from $instance"
                try {
                    # find the message using language or languageID or the 'session language' message if they specified 'all'. SMO will drop all related messages for an ID if the english message is dropped.
                    $userDefinedMessage = $server.UserDefinedMessages | Where-Object { $_.ID -eq $MessageID -and ($_.Language -in $languageName, $languageAlias -or $_.LanguageID -eq $langId -or ($Language -ieq "All" -and $_.Language -like "*english")) }
                    $userDefinedMessage.Drop()
                } catch {
                    Stop-Function -Message "Error occurred while trying to remove a message with id $MessageID from $instance" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}