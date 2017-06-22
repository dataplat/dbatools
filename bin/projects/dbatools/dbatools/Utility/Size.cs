using System;

namespace Sqlcollaborative.Dbatools
{
    namespace Utility
    {
        /// <summary>
        /// Class that reports File size.
        /// </summary>
        [Serializable]
        public class Size : IComparable<Size>, IComparable
        {
            /// <summary>
            /// Number of bytes contained in whatever object uses this object as a property
            /// </summary>
            public long Byte
            {
                get
                {
                    return _Byte;
                }
                set
                {
                    _Byte = value;
                }
            }
            private long _Byte = -1;

            /// <summary>
            /// Kilobyte representation of the bytes
            /// </summary>
            public double Kilobyte
            {
                get
                {
                    return ((double)_Byte / (double)1024);
                }
                set
                {

                }
            }

            /// <summary>
            /// Megabyte representation of the bytes
            /// </summary>
            public double Megabyte
            {
                get
                {
                    return ((double)_Byte / (double)1048576);
                }
                set
                {

                }
            }

            /// <summary>
            /// Gigabyte representation of the bytes
            /// </summary>
            public double Gigabyte
            {
                get
                {
                    return ((double)_Byte / (double)1073741824);
                }
                set
                {

                }
            }

            /// <summary>
            /// Terabyte representation of the bytes
            /// </summary>
            public double Terabyte
            {
                get
                {
                    return ((double)_Byte / (double)1099511627776);
                }
                set
                {

                }
            }

            /// <summary>
            /// Number if digits behind the dot.
            /// </summary>
            public int Digits
            {
                get
                {
                    return _Digits;
                }
                set
                {
                    if (value < 0) { _Digits = 0; }
                    else { _Digits = value; }
                }
            }
            private int _Digits = 2;

            /// <summary>
            /// Shows the default string representation of size
            /// </summary>
            /// <returns></returns>
            public override string ToString()
            {
                string format = "{0:N" + _Digits + "}";

                if (Terabyte > 1)
                {
                    return (String.Format(format, Terabyte) + " TB");
                }
                else if (Gigabyte > 1)
                {
                    return (String.Format(format, Gigabyte) + " GB");
                }
                else if (Megabyte > 1)
                {
                    return (String.Format(format, Megabyte) + " MB");
                }
                else if (Kilobyte > 1)
                {
                    return (String.Format(format, Kilobyte) + " KB");
                }
                else if (Byte > -1)
                {
                    return (String.Format(format, Byte) + " B");
                }
                else if (Byte == -1)
                    return "Unlimited";
                else { return ""; }
            }

            /// <summary>
            /// Simple equality test
            /// </summary>
            /// <param name="obj">The object to test it against</param>
            /// <returns>True if equal, false elsewise</returns>
            public override bool Equals(object obj)
            {
                return ((obj != null) && (obj is Size) && (this.Byte == ((Size)obj).Byte));
            }

            /// <summary>
            /// Meaningless, but required
            /// </summary>
            /// <returns>Some meaningless output</returns>
            public override int GetHashCode()
            {
                return this.Byte.GetHashCode();
            }

            /// <summary>
            /// Creates an empty size.
            /// </summary>
            public Size()
            {

            }

            /// <summary>
            /// Creates a size with some content
            /// </summary>
            /// <param name="Byte">The length in bytes to set the size to</param>
            public Size(long Byte)
            {
                this.Byte = Byte;
            }

            /// <summary>
            /// Some more interface implementation. Used to sort the object
            /// </summary>
            /// <param name="obj">The object to compare to</param>
            /// <returns>Something</returns>
            public int CompareTo(Size obj)
            {
                if (this.Byte == obj.Byte) { return 0; }
                if (this.Byte < obj.Byte) { return -1; }

                return 1;
            }

            /// <summary>
            /// Some more interface implementation. Used to sort the object
            /// </summary>
            /// <param name="obj">The object to compare to</param>
            /// <returns>Something</returns>
            public int CompareTo(Object obj)
            {
                try
                {
                    if (this.Byte == ((Size)obj).Byte) { return 0; }
                    if (this.Byte < ((Size)obj).Byte) { return -1; }

                    return 1;
                }
                catch { return 0; }
            }

            #region Operators
            /// <summary>
            /// Adds two sizes
            /// </summary>
            /// <param name="a">The first size to add</param>
            /// <param name="b">The second size to add</param>
            /// <returns>The sum of both sizes</returns>
            public static Size operator +(Size a, Size b)
            {
                return new Size(a.Byte + b.Byte);
            }

            /// <summary>
            /// Substracts two sizes
            /// </summary>
            /// <param name="a">The first size to substract</param>
            /// <param name="b">The second size to substract</param>
            /// <returns>The difference between both sizes</returns>
            public static Size operator -(Size a, Size b)
            {
                return new Size(a.Byte - b.Byte);
            }

            /// <summary>
            /// Implicitly converts int to size
            /// </summary>
            /// <param name="a">The number to convert</param>
            public static implicit operator Size(int a)
            {
                return new Size(a);
            }

            /// <summary>
            /// Implicitly converts size to int
            /// </summary>
            /// <param name="a">The size to convert</param>
            public static implicit operator Int32(Size a)
            {
                return (Int32)a._Byte;
            }

            /// <summary>
            /// Implicitly converts long to size
            /// </summary>
            /// <param name="a">The number to convert</param>
            public static implicit operator Size(long a)
            {
                return new Size(a);
            }

            /// <summary>
            /// Implicitly converts size to long
            /// </summary>
            /// <param name="a">The size to convert</param>
            public static implicit operator Int64(Size a)
            {
                return a._Byte;
            }

            /// <summary>
            /// Implicitly converts string to size
            /// </summary>
            /// <param name="a">The string to convert</param>
            public static implicit operator Size(String a)
            {
                return new Size(Int64.Parse(a));
            }

            /// <summary>
            /// Implicitly converts double to size
            /// </summary>
            /// <param name="a">The number to convert</param>
            public static implicit operator Size(double a)
            {
                return new Size((long)a);
            }

            /// <summary>
            /// Implicitly converts size to double
            /// </summary>
            /// <param name="a">The size to convert</param>
            public static implicit operator double(Size a)
            {
                return a._Byte;
            }
            #endregion Operators
        }
    }
}