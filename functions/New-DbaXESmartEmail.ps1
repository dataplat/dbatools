function New-DbaXESmartEmail {
    <#
    .SYNOPSIS
        This response type can be used to send an email each time an event is captured.

    .DESCRIPTION
        This response type can be used to send an email each time an event is captured.

    .PARAMETER SmtpServer
        Address of the SMTP server for outgoing mail.

    .PARAMETER Sender
        Sender's email address.

    .PARAMETER To
        Address of the To recipient(s).

    .PARAMETER Cc
        Address of the Cc recipient(s).

    .PARAMETER Bcc
        Address of the Bcc recipient(s).

    .PARAMETER Credential
        Credential object containing username and password used to authenticate on the SMTP server. When blank, no authentication is performed.

    .PARAMETER Subject
        Subject of the mail message. Accepts placeholders in the text.

        Placeholders are in the form {PropertyName}, where PropertyName is one of the fields or actions available in the Event object.

        For instance, a valid Subject in a configuration file looks like this: "An event of name {Name} occurred at {collection_time}"

    .PARAMETER Body
        Body of the mail message. The body can be static text or any property taken from the underlying event. See Subject for a description of how placeholders work.

    .PARAMETER Attachment
        Data to attach to the email message. At this time, it can be any of the fields/actions of the underlying event. The data from the field/action is attached to the message as an ASCII stream. A single attachment is supported.

    .PARAMETER AttachmentFileName
        File name to assign to the attachment.

    .PARAMETER PlainText
        If this switch is enabled, the email will be sent in plain text. By default, HTML formatting is used.

    .PARAMETER Event
        Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

    .PARAMETER Filter
        You can specify a filter expression by using this attribute. The filter expression is in the same form that you would use in a SQL query. For example, a valid example looks like this: duration > 10000 AND cpu_time > 10000

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent, SmartTarget
        Author: Chrissy LeMaire (@cl) | SmartTarget by Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaXESmartEmail

    .EXAMPLE
        PS C:\> $params = @{
        >> SmtpServer = "smtp.ad.local"
        >> To = "admin@ad.local"
        >> Sender = "reports@ad.local"
        >> Subject = "Query executed"
        >> Body = "Query executed at {collection_time}"
        >> Attachment = "batch_text"
        >> AttachmentFileName = "query.sql"
        >> }
        >>
        PS C:\> $emailresponse = New-DbaXESmartEmail @params
        PS C:\> Start-DbaXESmartTarget -SqlInstance sql2017 -Session querytracker -Responder $emailresponse

        Sends an email each time a querytracker event is captured.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory)]
        [string]$SmtpServer,
        [parameter(Mandatory)]
        [string]$Sender,
        [parameter(Mandatory)]
        [string[]]$To,
        [string[]]$Cc,
        [string[]]$Bcc,
        [pscredential]$Credential,
        [parameter(Mandatory)]
        [string]$Subject,
        [parameter(Mandatory)]
        [string]$Body,
        [string]$Attachment,
        [string]$AttachmentFileName,
        [string]$PlainText,
        [string[]]$Event,
        [string]$Filter,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\libraries\third-party\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll." -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($Pscmdlet.ShouldProcess("Creating new XESmartEmail Object")) {
            try {
                $email = New-Object -TypeName XESmartTarget.Core.Responses.EmailResponse
                $email.SmtpServer = $SmtpServer
                $email.Sender = $Sender
                $email.To = $To
                $email.Cc = $Cc
                $email.Bcc = $Bcc
                $email.Subject = $Subject
                $email.Body = $Body
                $email.Attachment = $Attachment
                $email.AttachmentFileName = $AttachmentFileName
                $email.HTMLFormat = ($PlainText -eq $false)
                if (Test-Bound -ParameterName "Event") {
                    $email.Events = $Event
                }
                if (Test-Bound -ParameterName "Filter") {
                    $email.Filter = $Filter
                }

                if ($Credential) {
                    $email.UserName = $Credential.UserName
                    $email.Password = $Credential.GetNetworkCredential().Password
                }

                $email
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
            }
        }
    }
}