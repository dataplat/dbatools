param($ModuleName = 'dbatools')

Describe "New-DbaXESmartEmail" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartEmail
        }
        $params = @(
            "SmtpServer",
            "Sender",
            "To",
            "Cc",
            "Bcc",
            "Credential",
            "Subject",
            "Body",
            "Attachment",
            "AttachmentFileName",
            "PlainText",
            "Event",
            "Filter",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $results = New-DbaXESmartEmail -SmtpServer smtp.ad.local -Sender me@me.com -To you@you.net -Subject Test -Body Sup -Event abc
            $results.SMTPServer | Should -Be 'smtp.ad.local'
            $results.Sender | Should -Be 'me@me.com'
            $results.To | Should -Be 'you@you.net'
            $results.Subject | Should -Be 'Test'
            $results.Events | Should -Contain 'abc'
            $results.HTMLFormat | Should -Be $false
        }
    }
}
