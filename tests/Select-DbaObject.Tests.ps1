#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Select-DbaObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "Property",
                "ExcludeProperty",
                "ExpandProperty",
                "Alias",
                "ScriptProperty",
                "ScriptMethod",
                "Unique",
                "Last",
                "First",
                "Skip",
                "SkipLast",
                "Wait",
                "Index",
                "ShowProperty",
                "ShowExcludeProperty",
                "TypeName",
                "KeepInputObject"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $script:object = [PSCustomObject]@{
            Foo  = 42
            Bar  = 18
            Tara = 21
        }

        $script:object2 = [PSCustomObject]@{
            Foo = 42000
            Bar = 23
        }

        $script:list = @()
        $script:list += $script:object
        $script:list += [PSCustomObject]@{
            Foo  = 23
            Bar  = 88
            Tara = 28
        }
    }

    It "renames Bar to Bar2" {
        ($script:object | Select-DbaObject -Property "Foo", "Bar as Bar2").PSObject.Properties.Name | Should -Be "Foo", "Bar2"
    }

    It "changes Bar to string" {
        ($script:object | Select-DbaObject -Property "Bar to string").Bar.GetType().FullName | Should -Be "System.String"
    }

    It "converts numbers to sizes" {
        ($script:object2 | Select-DbaObject -Property "Foo size KB:1").Foo | Should -Be 41
        ($script:object2 | Select-DbaObject -Property "Foo size KB:1:1").Foo | Should -Be "41 KB"
    }

    It "picks values from other variables" {
        ($script:object2 | Select-DbaObject -Property "Tara from object").Tara | Should -Be 21
    }

    It "picks values from the properties of the right object in a list" {
        ($script:object2 | Select-DbaObject -Property "Tara from List where Foo = Bar").Tara | Should -Be 28
    }

    It "sets the correct properties to show in whitelist mode" {
        $obj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Right = "Left" }
        $null = $obj | Select-DbaObject -ShowProperty Foo, Bar
        $obj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be "Foo", "Bar"
    }

    It "sets the correct properties to show in blacklist mode" {
        $obj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Right = "Left" }
        $null = $obj | Select-DbaObject -ShowExcludeProperty Foo
        $obj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be "Bar", "Right"
    }

    It "sets the correct typename" {
        $obj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Right = "Left" }
        $null = $obj | Select-DbaObject -TypeName "Foo.Bar"
        $obj.PSObject.TypeNames[0] | Should -Be "Foo.Bar"
    }

    It "adds properties without harming the original object when used with -KeepInputObject" {
        $item = Get-Item "$PSScriptRoot\Select-DbaObject.Tests.ps1"
        $modItem = $item | Select-DbaObject "Length as Size size KB:1:1" -KeepInputObject
        $modItem.GetType().FullName | Should -Be "System.IO.FileInfo"
        $modItem.Size | Should -BeLike "* KB"
    }
}