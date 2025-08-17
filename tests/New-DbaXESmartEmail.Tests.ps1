#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaXESmartEmail",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $results = New-DbaXESmartEmail -SmtpServer "smtp.ad.local" -Sender "me@me.com" -To "you@you.net" -Subject "Test" -Body "Sup" -Event "abc"
            $results.SMTPServer | Should -Be "smtp.ad.local"
            $results.Sender | Should -Be "me@me.com"
            $results.To | Should -Be "you@you.net"
            $results.Subject | Should -Be "Test"
            $results.Events | Should -Contain "abc"
            $results.HTMLFormat | Should -Be $false
        }
    }
}