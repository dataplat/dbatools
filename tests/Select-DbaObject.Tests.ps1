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
        $object = [PSCustomObject]@{
            Foo  = 42
            Bar  = 18
            Tara = 21
        }

        $object2 = [PSCustomObject]@{
            Foo = 42000
            Bar = 23
        }

        $list = @()
        $list += $object
        $list += [PSCustomObject]@{
            Foo  = 23
            Bar  = 88
            Tara = 28
        }
    }

    It "renames Bar to Bar2" {
        ($object | Select-DbaObject -Property "Foo", "Bar as Bar2").PSObject.Properties.Name | Should -Be "Foo", "Bar2"
    }

    It "changes Bar to string" {
        ($object | Select-DbaObject -Property "Bar to string").Bar.GetType().FullName | Should -Be "System.String"
    }

    It "converts numbers to sizes" {
        ($object2 | Select-DbaObject -Property "Foo size KB:1").Foo | Should -Be 41
        ($object2 | Select-DbaObject -Property "Foo size KB:1:1").Foo | Should -Be "41 KB"
    }

    It "picks values from other variables" {
        ($object2 | Select-DbaObject -Property "Tara from object").Tara | Should -Be 21
    }

    It "picks values from the properties of the right object in a list" {
        ($object2 | Select-DbaObject -Property "Tara from List where Foo = Bar").Tara | Should -Be 28
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

    Context "Output Validation" {
        It "Returns PSCustomObject by default when transforming properties" {
            $result = $object | Select-DbaObject -Property "Foo", "Bar as Bar2"
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the transformed properties in output" {
            $result = $object | Select-DbaObject -Property "Foo", "Bar as Bar2"
            $result.PSObject.Properties.Name | Should -Contain "Foo"
            $result.PSObject.Properties.Name | Should -Contain "Bar2"
            $result.PSObject.Properties.Name | Should -Not -Contain "Bar"
        }

        It "Preserves original object type when -KeepInputObject is used" {
            $item = Get-Item "$PSScriptRoot\Select-DbaObject.Tests.ps1"
            $result = $item | Select-DbaObject "Length as Size" -KeepInputObject
            $result.GetType().FullName | Should -Be "System.IO.FileInfo"
        }

        It "Adds custom typename when -TypeName is specified" {
            $result = $object | Select-DbaObject -Property "Foo", "Bar" -TypeName "CustomType"
            $result.PSObject.TypeNames[0] | Should -Be "CustomType"
        }

        It "Has properties added by -KeepInputObject" {
            $item = Get-Item "$PSScriptRoot\Select-DbaObject.Tests.ps1"
            $result = $item | Select-DbaObject "Length as Size" -KeepInputObject
            $result.PSObject.Properties.Name | Should -Contain "Size"
            $result.PSObject.Properties.Name | Should -Contain "Length"
        }

        It "Sets default display properties when -ShowProperty is used" {
            $testObj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Test = "Value" }
            $null = $testObj | Select-DbaObject -ShowProperty Foo, Bar
            $testObj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be "Foo", "Bar"
        }

        It "Excludes properties from default display when -ShowExcludeProperty is used" {
            $testObj = [PSCustomObject]@{ Foo = "Bar"; Bar = 42; Test = "Value" }
            $null = $testObj | Select-DbaObject -ShowExcludeProperty Foo
            $testObj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Contain "Bar"
            $testObj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Contain "Test"
            $testObj.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Not -Contain "Foo"
        }
    }
}