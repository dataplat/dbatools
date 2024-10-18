param($ModuleName = 'dbatools')

Describe "Select-DbaObject" {
    BeforeAll {
        $commandName = $PSCommandPath.Split('\')[-1].Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $global:object = [PSCustomObject]@{
            Foo  = 42
            Bar  = 18
            Tara = 21
        }

        $global:object2 = [PSCustomObject]@{
            Foo = 42000
            Bar = 23
        }

        $global:list = @()
        $global:list += $object
        $global:list += [PSCustomObject]@{
            Foo  = 23
            Bar  = 88
            Tara = 28
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Select-DbaObject
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Management.Automation.PSObject
        }
        It "Should have Property as a parameter" {
            $CommandUnderTest | Should -HaveParameter Property -Type Dataplat.Dbatools.Parameter.DbaSelectParameter[]
        }
        It "Should have ExcludeProperty as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeProperty -Type System.String[]
        }
        It "Should have ExpandProperty as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExpandProperty -Type System.String
        }
        It "Should have Alias as a parameter" {
            $CommandUnderTest | Should -HaveParameter Alias -Type Dataplat.Dbatools.Parameter.SelectAliasParameter[]
        }
        It "Should have ScriptProperty as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptProperty -Type Dataplat.Dbatools.Parameter.SelectScriptPropertyParameter[]
        }
        It "Should have ScriptMethod as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptMethod -Type Dataplat.Dbatools.Parameter.SelectScriptMethodParameter[]
        }
        It "Should have Unique as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Unique -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Last as a parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type System.Int32
        }
        It "Should have First as a parameter" {
            $CommandUnderTest | Should -HaveParameter First -Type System.Int32
        }
        It "Should have Skip as a parameter" {
            $CommandUnderTest | Should -HaveParameter Skip -Type System.Int32
        }
        It "Should have SkipLast as a parameter" {
            $CommandUnderTest | Should -HaveParameter SkipLast -Type System.Int32
        }
        It "Should have Wait as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Wait -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Index as a parameter" {
            $CommandUnderTest | Should -HaveParameter Index -Type System.Int32[]
        }
        It "Should have ShowProperty as a parameter" {
            $CommandUnderTest | Should -HaveParameter ShowProperty -Type System.String[]
        }
        It "Should have ShowExcludeProperty as a parameter" {
            $CommandUnderTest | Should -HaveParameter ShowExcludeProperty -Type System.String[]
        }
        It "Should have TypeName as a parameter" {
            $CommandUnderTest | Should -HaveParameter TypeName -Type System.String
        }
        It "Should have KeepInputObject as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepInputObject -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        It "renames Bar to Bar2" {
            ($object | Select-DbaObject -Property 'Foo', 'Bar as Bar2').PSObject.Properties.Name | Should -Be @('Foo', 'Bar2')
        }

        It "changes Bar to string" {
            ($object | Select-DbaObject -Property 'Bar to string').Bar.GetType().FullName | Should -Be 'System.String'
        }

        It "converts numbers to sizes" {
            ($object2 | Select-DbaObject -Property 'Foo size KB:1').Foo | Should -Be 41
            ($object2 | Select-DbaObject -Property 'Foo size KB:1:1').Foo | Should -Be "41 KB"
        }

        It "picks values from other variables" {
            ($object2 | Select-DbaObject -Property 'Tara from object').Tara | Should -Be 21
        }

        It "picks values from the properties of the right object in a list" {
            ($object2 | Select-DbaObject -Property 'Tara from List where Foo = Bar').Tara | Should -Be 28
        }

        It "sets the correct properties to show in whitelist mode" {
            $obj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Right = "Left" }
            $null = $obj | Select-DbaObject -ShowProperty Foo, Bar
            $obj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @('Foo', 'Bar')
        }

        It "sets the correct properties to show in blacklist mode" {
            $obj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Right = "Left" }
            $null = $obj | Select-DbaObject -ShowExcludeProperty Foo
            $obj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @('Bar', 'Right')
        }

        It "sets the correct typename" {
            $obj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Right = "Left" }
            $null = $obj | Select-DbaObject -TypeName 'Foo.Bar'
            $obj.PSObject.TypeNames[0] | Should -Be 'Foo.Bar'
        }

        It "adds properties without harming the original object when used with -KeepInputObject" {
            $item = Get-Item "$PSScriptRoot\Select-DbaObject.Tests.ps1"
            $modItem = $item | Select-DbaObject "Length as Size size KB:1:1" -KeepInputObject
            $modItem.GetType().FullName | Should -Be 'System.IO.FileInfo'
            $modItem.Size | Should -BeLike '* KB'
        }
    }
}
