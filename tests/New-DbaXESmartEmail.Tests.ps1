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
        It "Should have SmtpServer parameter" {
            $CommandUnderTest | Should -HaveParameter SmtpServer -Type String
        }
        It "Should have Sender parameter" {
            $CommandUnderTest | Should -HaveParameter Sender -Type String
        }
        It "Should have To parameter" {
            $CommandUnderTest | Should -HaveParameter To -Type String[]
        }
        It "Should have Cc parameter" {
            $CommandUnderTest | Should -HaveParameter Cc -Type String[]
        }
        It "Should have Bcc parameter" {
            $CommandUnderTest | Should -HaveParameter Bcc -Type String[]
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Subject parameter" {
            $CommandUnderTest | Should -HaveParameter Subject -Type String
        }
        It "Should have Body parameter" {
            $CommandUnderTest | Should -HaveParameter Body -Type String
        }
        It "Should have Attachment parameter" {
            $CommandUnderTest | Should -HaveParameter Attachment -Type String
        }
        It "Should have AttachmentFileName parameter" {
            $CommandUnderTest | Should -HaveParameter AttachmentFileName -Type String
        }
        It "Should have PlainText parameter" {
            $CommandUnderTest | Should -HaveParameter PlainText -Type String
        }
        It "Should have Event parameter" {
            $CommandUnderTest | Should -HaveParameter Event -Type String[]
        }
        It "Should have Filter parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
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
