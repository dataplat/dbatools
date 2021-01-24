function Remove-DbaCustomError {
    <#
    .SYNOPSIS
        Removes a user defined message from sys.messages. This command does not support Azure SQL Database.

    .DESCRIPTION
        This command provides a wrapper for the sp_dropmessage system procedure that allows for user defined messages to be removed from sys.messages.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER MessageID
        An integer between 50001 and 2147483647.

    .PARAMETER Language
        Language for the message to be removed. The valid values for Language are contained in the Name and Alias columns from sys.syslanguages.

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
        https://dbatools.io/Remove-DbaCustomError

    .EXAMPLE
        PS C:\> Remove-DbaCustomError -SqlInstance localhost, serverName2 -MessageID 70001 -Language "French"

        Removes the custom message on the localhost and serverName2 instances with ID 70001 and language French.

    .EXAMPLE
        PS C:\> Remove-DbaCustomError -SqlInstance localhost, serverName2 -MessageID 70001 -Language "All"

        Removes all custom messages on the localhost and serverName2 instances with ID 70001.
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
        $removedMessages = @()

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Language -ine "All") {
                $languageDetails = $server.Query("SELECT TOP 1 name, alias, msglangid FROM sys.syslanguages WHERE name = '$Language' OR alias = '$Language'")

                if ((Test-Bound Language) -and $null -eq $languageDetails) {
                    Stop-Function -Message "$server does not have the $Language installed" -Target $instance -Continue
                }

                $languageName = $languageDetails.name
                $languageAlias = $languageDetails.alias
                $langId = $languageDetails.msglangid
            }

            if ($Pscmdlet.ShouldProcess("Removing server message with id $MessageID from $server")) {
                Write-Message -Level Verbose -Message "Removing server message with id $MessageID and language $Language from $server"
                try {
                    # find the message using language or languageID or the 'session language' message if they specified 'all'. SMO will drop all related messages for an ID if the english message is dropped.
                    $userDefinedMessage = $server.UserDefinedMessages | Where-Object { $_.ID -eq $MessageID -and ($_.Language -in $languageName, $languageAlias -or $_.LanguageID -eq $langId -or ($Language -ieq "All" -and $_.Language -like "*english")) }
                    $userDefinedMessage.Drop()
                    $removedMessages += $userDefinedMessage
                } catch {
                    Stop-Function -Message "Error occurred while trying to remove a message with id $MessageID from $server" -ErrorRecord $_ -Continue
                }
            }
        }

        $removedMessages
    }
}