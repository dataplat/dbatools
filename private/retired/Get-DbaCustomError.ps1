function Get-DbaCustomError {
    <#
    .SYNOPSIS
        Retrieves user-defined error messages from SQL Server instances for auditing and documentation.

    .DESCRIPTION
        Retrieves all custom error messages that have been added to SQL Server using sp_addmessage or through SQL Server Management Studio. These user-defined error messages are stored in the sys.messages system catalog and are commonly used by applications for business logic validation and custom error handling. This function helps DBAs inventory custom errors across multiple instances during migrations, troubleshooting, or compliance audits.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, Error
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCustomError

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.UserDefinedMessage

        Returns one UserDefinedMessage object per custom error message found in sys.messages on the target SQL Server instance(s). When multiple instances are specified, all custom errors from all instances are returned.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server host
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ID: The custom error message ID (50001-2147483647)
        - Text: The text of the custom error message (max 255 characters)
        - LanguageID: The language ID (numeric identifier from sys.syslanguages)
        - Language: The language name (e.g., "English", "French", "Deutsch")

        Additional properties available (from SMO UserDefinedMessage object):
        - Severity: The severity level of the error (1-25 integer)
        - IsLogged: Boolean indicating if the error is logged to the Windows Application and SQL Server error logs
        - Parent: Reference to the parent SMO Server object

        All properties from the base SMO object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaCustomError -SqlInstance localhost

        Returns all Custom Error Message(s) on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaCustomError -SqlInstance localhost, sql2016

        Returns all Custom Error Message(s) for the local and sql2016 SQL Server instances

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($customError in $server.UserDefinedMessages) {
                Add-Member -Force -InputObject $customError -MemberType NoteProperty -Name ComputerName -value $customError.Parent.ComputerName
                Add-Member -Force -InputObject $customError -MemberType NoteProperty -Name InstanceName -value $customError.Parent.ServiceName
                Add-Member -Force -InputObject $customError -MemberType NoteProperty -Name SqlInstance -value $customError.Parent.DomainInstanceName

                Select-DefaultView -InputObject $customError -Property ComputerName, InstanceName, SqlInstance, ID, Text, LanguageID, Language
            }
        }
    }
}