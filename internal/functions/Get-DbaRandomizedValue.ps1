function Get-DbaRandomizedValue {
    <#
    .SYNOPSIS
        This function will generate a random value for a specific data type or bogus type and subtype

    .DESCRIPTION
        Generates a random value based on the assigned sql data type or bogus type with sub type.
        It supports a wide range of sql data types and an entire dictionary of various random values.

    .PARAMETER DataType
        The target SQL Server instance or instances.

        Supported data types are bigint, bit, bool, char, date, datetime, datetime2, decimal, int, float, guid, money, numeric, nchar, ntext, nvarchar, real, smalldatetime, smallint, text, time, tinyint, uniqueidentifier, userdefineddatatype, varchar

    .PARAMETER RandomizerType
        Bogus type to use.

        Supported types are Address, Commerce, Company, Database, Date, Finance, Hacker, Hashids, Image, Internet, Lorem, Name, Person, Phone, Random, Rant, System

    .PARAMETER RandomizerSubType
        Subtype to use.

    .PARAMETER Min
        Minimum value used to generate certain lengths of values. Default is 0

    .PARAMETER Max
        Maximum value used to generate certain lengths of values. Default is 255

    .PARAMETER Precision
        Precision used for numeric sql data types like decimal, numeric, real and float

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER Locale
        Set the local to enable certain settings in the masking. The default is 'en'

    .PARAMETER DisplayLegend
        Get all the possibilities for the randomizer

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, DataGeneration
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue -DataType bit

        Will return either a 1 or 0

    .EXAMPLE
        Get-DbaRandomizedValue -DataType int

        Will generate a number between -2147483648 and 2147483647

    .EXAMPLE
        Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue

    #>
    [CmdLetBinding()]
    param(
        [string]$DataType,
        [string]$RandomizerType,
        [string]$RandomizerSubType,
        [int64]$Min = 1,
        [int64]$Max = 255,
        [int]$Precision = 2,
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Locale = 'en',
        [switch]$DisplayLegend,
        [switch]$EnableException
    )


    begin {
        # Get all the random possibilities
        $randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.bogustypes.csv") | Group-Object {$_.Type}

        if ($DisplayLegend) {
            $randomizerTypes.Group

            return
        }

        # Create the faker objects
        Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\Bogus.dll")
        $faker = New-Object Bogus.Faker($Locale)



        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check the variables
        if (-not $DataType -and -not $RandomizerType -and -not $RandomizerSubType) {
            Stop-Function -Message "Please use one of the variables" -Continue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $randomizerTypes.Group | Where-Object Subtype -eq $RandomizerSubType | Select-Object Type -ExpandProperty Type
        }

        if ($DataType -and $DataType.ToLower() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin ($randomizerTypes.Group.Type | Select-Object -Unique)) {
                Stop-Function -Message "Invalid bogus type" -Continue -Target $RandomizerType
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin ($randomizerTypes.Group.RandomizerSubType | Select-Object -Unique)) {
                Stop-Function -Message "Invalid sub type" -Continue -Target $RandomizerSubType
            }

            $bogusRandomizerSubTypes = $randomizerTypes.Group | Where-Object Type -eq 'Name' | Select-Object RandomizerSubType -ExpandProperty RandomizerSubType

            if ($RandomizerSubType -notin $bogusRandomizerSubTypes) {
                Stop-Function -Message "Invalid bogus type with sub type combination" -Continue -Target $RandomizerSubType
            }
        }

        if ($Min -gt $Max) {
            Stop-Function -Message "Min value cannot be greater than max value" -Continue -Target $Min
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($DataType) {

            switch ($DataType.ToLower()) {
                'bigint' {
                    if ($Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }
                }

                { $psitem -in 'bit', 'bool' } {
                    if ($faker.System.Random.Bool()) {
                        1
                    } else {
                        0
                    }
                }
                { $psitem -match 'date' } {
                    if ($columnobject.MinValue -or $columnobject.MaxValue) {
                        ($faker.Date.Between($nowmin, $nowmax)).ToString("yyyyMMdd")
                    } else {
                        ($faker.Date.Past()).ToString("yyyyMMdd")
                    }
                }
                { $psitem -in 'decimal', 'float', 'money', 'numeric', 'real'} {
                    $faker.Finance.Amount($Min, $Max, $Precision)
                }
                'int' {
                    if ($Min -lt -2147483648) {
                        $Min = -2147483648
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 2147483647) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }

                    $faker.System.Random.Int($Min, $Max)

                }
                'smallint' {
                    if ($Min -lt -32768) {
                        $Min = 32768
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 32767) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }

                    $faker.System.Random.Int($Min, $Max)
                }
                'time' {
                    ($faker.Date.Past()).ToString("h:mm tt zzz")
                }
                'tinyint' {
                    if ($Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 255) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }

                    $faker.System.Random.Int($Min, $Max)
                }
                { $psitem -in 'uniqueidentifier', 'guid' } {
                    $faker.System.Random.Guid().Guid
                }
                'userdefineddatatype' {
                    if ($Max -eq 1) {
                        if ($faker.System.Random.Bool()) {
                            1
                        } else {
                            0
                        }
                    } else {
                        $null
                    }
                }
                { $psitem -in 'char', 'nchar', 'nvarchar', 'varchar' } {
                    $faker.Random.String2($Min, $Max, $CharacterString)
                }

            }

        } else {



        }

    }




}