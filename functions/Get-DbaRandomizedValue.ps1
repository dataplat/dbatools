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

    .PARAMETER Format
        Use specilized formatting with certain randomizer types like phone number.

    .PARAMETER Symbol
        Use a symbol in front of the value i.e. $100,12

    .PARAMETER Separator
        Some masking types support separators

    .PARAMETER Value
        This is the value that needs to be used for several possible transformations.
        One example is the subtype "Shuffling" where the value will be shuffled.

    .PARAMETER Locale
        Set the local to enable certain settings in the masking. The default is 'en'

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
        Get-DbaRandomizedValue -RandomizerSubType Zipcode

        Generates a random zipcode

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode -Format "#### ##"

        Generates a random zipcode like "1234 56"

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType PhoneNumber -Format "(###) #######"

        Generates a random phonenumber like "(123) 4567890"

    #>
    [CmdLetBinding()]
    param(
        [string]$DataType,
        [string]$RandomizerType,
        [string]$RandomizerSubType,
        [object]$Min,
        [object]$Max,
        [int]$Precision = 2,
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Format,
        [string]$Symbol,
        [string]$Separator,
        [string]$Value,
        [string]$Locale = 'en',
        [switch]$EnableException
    )


    begin {
        # Create faker object
        if (-not $script:faker) {
            $script:faker = New-Object Bogus.Faker($Locale)
        }

        # Get all the random possibilities
        if (-not $script:randomizerTypes) {
            $script:randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.randomizertypes.csv") | Group-Object { $_.Type }
        }

        if (-not $script:uniquesubtypes) {
            $script:uniquesubtypes = $script:randomizerTypes.Group | Where-Object Subtype -eq $RandomizerSubType | Select-Object Type -ExpandProperty Type -First 1
        }

        if (-not $script:uniquerandomizertypes) {
            $script:uniquerandomizertypes = ($script:randomizerTypes.Group.Type | Select-Object -Unique)
        }

        if (-not $script:uniquerandomizersubtype) {
            $script:uniquerandomizersubtype = ($script:randomizerTypes.Group.SubType | Select-Object -Unique)
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check the variables
        if (-not $DataType -and -not $RandomizerType -and -not $RandomizerSubType) {
            Stop-Function -Message "Please use one of the variables i.e. -DataType, -RandomizerType or -RandomizerSubType" -Continue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $script:uniquesubtypes
        }

        if ($DataType -and $DataType.ToLowerInvariant() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin $script:uniquerandomizertypes) {
                Stop-Function -Message "Invalid randomizer type" -Continue -Target $RandomizerType
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin $script:uniquerandomizersubtype) {
                Stop-Function -Message "Invalid randomizer sub type" -Continue -Target $RandomizerSubType
            }

            if ($RandomizerSubType.ToLowerInvariant() -eq 'shuffle' -and $null -eq $Value) {
                Stop-Function -Message "Value cannot be empty when using sub type 'Shuffle'" -Continue -Target $RandomizerSubType
            }
        }

        if (-not $Min) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Min = 1
            }
        }

        if (-not $Max) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Max = 255
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($DataType) {

            switch ($DataType.ToLowerInvariant()) {
                'bigint' {
                    if (-not $Min -or $Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }
                }

                { $psitem -in 'bit', 'bool' } {
                    if ($script:faker.Random.Bool()) {
                        1
                    } else {
                        0
                    }
                }
                'date' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime2' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                { $psitem -in 'decimal', 'float', 'money', 'numeric', 'real' } {
                    $script:faker.Finance.Amount($Min, $Max, $Precision)
                }
                'int' {
                    if (-not $Min -or $Min -lt -2147483648) {
                        $Min = -2147483648
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 2147483647 -or $Max -lt $Min) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)

                }
                'smalldatetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'smallint' {
                    if (-not $Min -or $Min -lt -32768) {
                        $Min = 32768
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 32767 -or $Max -lt $Min) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                'time' {
                    ($script:faker.Date.Past()).ToString("HH:mm:ss.fffffff")
                }
                'tinyint' {
                    if (-not $Min -or $Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 255 -or $Max -lt $Min) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                { $psitem -in 'uniqueidentifier', 'guid' } {
                    $script:faker.System.Random.Guid().Guid
                }
                'userdefineddatatype' {
                    if ($Max -eq 1) {
                        if ($script:faker.System.Random.Bool()) {
                            1
                        } else {
                            0
                        }
                    } else {
                        $null
                    }
                }
                { $psitem -in 'char', 'nchar', 'nvarchar', 'varchar' } {
                    $script:faker.Random.String2($Min, $Max, $CharacterString)
                }

            }

        } else {

            $randSubType = $RandomizerSubType.ToLowerInvariant()

            switch ($RandomizerType.ToLowerInvariant()) {
                'address' {

                    if ($randSubType -in 'latitude', 'longitude') {
                        $script:faker.Address.Latitude($Min, $Max)
                    } elseif ($randSubType -eq 'zipcode') {
                        if ($Format) {
                            $script:faker.Address.ZipCode("$($Format)")
                        } else {
                            $script:faker.Address.ZipCode()
                        }
                    } else {
                        $script:faker.Address.$RandomizerSubType()
                    }

                }
                'commerce' {
                    if ($randSubType -eq 'categories') {
                        $script:faker.Commerce.Categories($Max)
                    } elseif ($randSubType -eq 'departments') {
                        $script:faker.Commerce.Department($Max)
                    } elseif ($randSubType -eq 'price') {
                        $script:faker.Commerce.Price($min, $Max, $Precision, $Symbol)
                    } else {
                        $script:faker.Commerce.$RandomizerSubType()
                    }

                }
                'company' {
                    $script:faker.Company.$RandomizerSubType()
                }
                'database' {
                    $script:faker.Database.$RandomizerSubType()
                }
                'date' {
                    if ($randSubType -eq 'between') {

                        if (-not $Min) {
                            Stop-Function -Message "Please set the minimum value for the date" -Continue -Target $Min
                        }

                        if (-not $Max) {
                            Stop-Function -Message "Please set the maximum value for the date" -Continue -Target $Max
                        }

                        if ($Min -gt $Max) {
                            Stop-Function -Message "The minimum value for the date cannot be later than maximum value" -Continue -Target $Min
                        } else {
                            ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'past') {
                        if ($Max) {
                            if ($Min) {
                                $yearsToGoBack = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoBack = 1
                            }

                            $script:faker.Date.Past($yearsToGoBack, $Max).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Past().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'future') {
                        if ($Min) {
                            if ($Max) {
                                $yearsToGoForward = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoForward = 1
                            }

                            $script:faker.Date.Future($yearsToGoForward, $Min).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Future().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }

                    } elseif ($randSubType -eq 'recent') {
                        $script:faker.Date.Recent().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } elseif ($randSubType -eq 'random') {
                        if ($Min -or $Max) {
                            if (-not $Min) {
                                $Min = Get-Date
                            }

                            if (-not $Max) {
                                $Max = (Get-Date).AddYears(1)
                            }

                            ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } else {
                        $script:faker.Date.$RandomizerSubType()
                    }
                }
                'finance' {
                    if ($randSubType -eq 'account') {
                        $script:faker.Finance.Account($Max)
                    } elseif ($randSubType -eq 'amount') {
                        $script:faker.Finance.Amount($Min, $Max, $Precision)
                    } else {
                        $script:faker.Finance.$RandomizerSubType()
                    }
                }
                'hacker' {
                    $script:faker.Hacker.$RandomizerSubType()
                }
                'image' {
                    $script:faker.Image.$RandomizerSubType()
                }
                'internet' {
                    if ($randSubType -eq 'password') {
                        $script:faker.Internet.Password($Max)
                    } elseif ($randSubType -eq 'mac') {
                        if ($Separator) {
                            $script:faker.Internet.Mac($Separator)
                        } else {
                            if (-not $Format -or $Format -eq "##:##:##:##:##:##") {
                                $script:faker.Internet.Mac()
                            } elseif ($Format -eq "############") {
                                $script:faker.Internet.Mac("")
                            } else {
                                $newMacArray = $Format.ToCharArray()

                                $macAddress = $script:faker.Internet.Mac("")
                                $macArray = $macAddress.ToCharArray()

                                $macIndex = 0
                                for ($i = 0; $i -lt $formatArray.Count; $i++) {
                                    if ($newMacArray[$i] -eq "#") {
                                        $newMacArray[$i] = $macArray[$macIndex]
                                        $macIndex++
                                    }
                                }

                                $newMacArray -join ""
                            }
                        }
                    } else {
                        $script:faker.Internet.$RandomizerSubType()
                    }
                }
                'lorem' {
                    if ($randSubType -eq 'paragraph') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraph($Min)

                    } elseif ($randSubType -eq 'paragraphs') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraphs($Min)

                    } elseif ($randSubType -eq 'letter') {
                        $script:faker.Lorem.Letter($Max)
                    } elseif ($randSubType -eq 'lines') {
                        $script:faker.Lorem.Lines($Max)
                    } elseif ($randSubType -eq 'sentence') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentence($Min, $Max)

                    } elseif ($randSubType -eq 'sentences') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentences($Min, $Max)

                    } elseif ($randSubType -eq 'slug') {
                        $script:faker.Lorem.Slug($Max)
                    } elseif ($randSubType -eq 'words') {
                        $script:faker.Lorem.Words($Max)
                    } else {
                        $script:faker.Lorem.$RandomizerSubType()
                    }
                }
                'name' {
                    $script:faker.Name.$RandomizerSubType()
                }
                'person' {
                    if ($randSubType -eq "phone") {
                        if ($Format) {
                            $script:faker.Phone.PhoneNumber($Format)
                        } else {
                            $script:faker.Phone.PhoneNumber()
                        }
                    } else {
                        $script:faker.Person.$RandomizerSubType
                    }
                }
                'phone' {
                    if ($Format) {
                        $script:faker.Phone.PhoneNumber($Format)
                    } else {
                        $script:faker.Phone.PhoneNumber()
                    }
                }
                'random' {
                    if ($randSubType -in 'byte', 'char', 'decimal', 'double', 'even', 'float', 'int', 'long', 'number', 'odd', 'sbyte', 'short', 'uint', 'ulong', 'ushort') {
                        $script:faker.Random.$RandomizerSubType($Min, $Max)
                    } elseif ($randSubType -eq 'bytes') {
                        $script:faker.Random.Bytes($Max)
                    } elseif ($randSubType -in 'string', 'string2') {
                        $script:faker.Random.String2([int]$Min, [int]$Max, $CharacterString)
                    } elseif ($randSubType -eq 'shuffle') {
                        $commaIndex = $value.IndexOf(",")
                        $dotIndex = $value.IndexOf(".")

                        $Value = (($Value -replace ',', '') -replace '\.', '')

                        $newValue = ($script:faker.Random.Shuffle($Value) -join '')

                        if ($commaIndex -ne -1) {
                            $newValue = $newValue.Insert($commaIndex, ',')
                        }

                        if ($dotIndex -ne -1) {
                            $newValue = $newValue.Insert($dotIndex, '.')
                        }

                        $newValue
                    } else {
                        $script:faker.Random.$RandomizerSubType()
                    }
                }
                'rant' {
                    if ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Review($script:faker.Commerce.Product())
                    } elseif ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Reviews($script:faker.Commerce.Product(), $Max)
                    }
                }
                'system' {
                    $script:faker.System.$RandomizerSubType()
                }
            }
        }
    }
}