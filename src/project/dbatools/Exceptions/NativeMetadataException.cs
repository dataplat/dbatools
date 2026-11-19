using System;

namespace Dataplat.Dbatools.Exceptions
{
    /// <summary>A metadata getter requiring script execution cannot run on a native path.</summary>
    public sealed class NativeMetadataException : NotSupportedException
    {
        /// <summary>Identifies the metadata member that cannot be read natively.</summary>
        public NativeMetadataException(string message) : base(message) { }

        internal static bool IsInChain(Exception exception)
        {
            for (Exception current = exception; current != null; current = current.InnerException)
                if (current is NativeMetadataException)
                    return true;
            return false;
        }
    }
}
