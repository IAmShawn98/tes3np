# Native Windows Explorer-style unified ZIP/folder chooser.
# The standard Common Item Dialog cannot return files AND directories via its
# stock Open button. Add "Use This Folder" to the SAME native file dialog:
# Open -> ZIP, Use This Folder -> selected/current extracted folder.
# This helper selects a path only; it never modifies game files.
param(
    [string]$ResultFile = '',
    [long]$OwnerHwnd = 0,
    [switch]$SmokeTest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = @'
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace TES3NP.Expansion
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct FilterSpec
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string Name;
        [MarshalAs(UnmanagedType.LPWStr)] public string Pattern;
    }

    [ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileDialog
    {
        [PreserveSig] int Show(IntPtr owner);
        [PreserveSig] int SetFileTypes(uint count, [MarshalAs(UnmanagedType.LPArray)] FilterSpec[] specs);
        [PreserveSig] int SetFileTypeIndex(uint index);
        [PreserveSig] int GetFileTypeIndex(out uint index);
        [PreserveSig] int Advise(IFileDialogEvents events, out uint cookie);
        [PreserveSig] int Unadvise(uint cookie);
        [PreserveSig] int SetOptions(uint options);
        [PreserveSig] int GetOptions(out uint options);
        [PreserveSig] int SetDefaultFolder(IShellItem folder);
        [PreserveSig] int SetFolder(IShellItem folder);
        [PreserveSig] int GetFolder(out IShellItem folder);
        [PreserveSig] int GetCurrentSelection(out IShellItem item);
        [PreserveSig] int SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int GetFileName(out IntPtr name);
        [PreserveSig] int SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
        [PreserveSig] int SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        [PreserveSig] int SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        [PreserveSig] int GetResult(out IShellItem item);
        [PreserveSig] int AddPlace(IShellItem item, uint alignment);
        [PreserveSig] int SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string ext);
        [PreserveSig] int Close(int result);
        [PreserveSig] int SetClientGuid(ref Guid guid);
        [PreserveSig] int ClearClientData();
        [PreserveSig] int SetFilter(IntPtr filter);
    }

    [ComImport, Guid("E6FDD21A-163F-4975-9C8C-A69F1BA37034"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileDialogCustomize
    {
        [PreserveSig] int EnableOpenDropDown(uint id);
        [PreserveSig] int AddMenu(uint id, [MarshalAs(UnmanagedType.LPWStr)] string label);
        [PreserveSig] int AddPushButton(uint id, [MarshalAs(UnmanagedType.LPWStr)] string label);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        [PreserveSig] int BindToHandler(IntPtr bindContext, ref Guid bhid, ref Guid iid, out IntPtr result);
        [PreserveSig] int GetParent(out IShellItem parent);
        [PreserveSig] int GetDisplayName(uint form, out IntPtr name);
        [PreserveSig] int GetAttributes(uint mask, out uint attributes);
        [PreserveSig] int Compare(IShellItem other, uint hint, out int order);
    }

    [ComVisible(true), Guid("973510DB-7D7F-452B-8975-74A85828D354"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileDialogEvents
    {
        [PreserveSig] int OnFileOk(IFileDialog dialog);
        [PreserveSig] int OnFolderChanging(IFileDialog dialog, IShellItem folder);
        [PreserveSig] int OnFolderChange(IFileDialog dialog);
        [PreserveSig] int OnSelectionChange(IFileDialog dialog);
        [PreserveSig] int OnShareViolation(IFileDialog dialog, IShellItem item, out uint response);
        [PreserveSig] int OnTypeChange(IFileDialog dialog);
        [PreserveSig] int OnOverwrite(IFileDialog dialog, IShellItem item, out uint response);
    }

    [ComVisible(true), Guid("36116642-D713-4B97-9B83-7484A9D00433"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileDialogControlEvents
    {
        [PreserveSig] int OnItemSelected(IFileDialogCustomize dialog, uint controlId, uint itemId);
        [PreserveSig] int OnButtonClicked(IFileDialogCustomize dialog, uint controlId);
        [PreserveSig] int OnCheckButtonToggled(IFileDialogCustomize dialog, uint controlId, [MarshalAs(UnmanagedType.Bool)] bool isChecked);
        [PreserveSig] int OnControlActivating(IFileDialogCustomize dialog, uint controlId);
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class DialogEvents : IFileDialogEvents, IFileDialogControlEvents
    {
        private const uint ChooseFolderButton = 4107;
        private readonly IFileDialog fileDialog;
        internal string ChosenFolder;

        internal DialogEvents(IFileDialog dialog) { fileDialog = dialog; }

        public int OnButtonClicked(IFileDialogCustomize customize, uint controlId)
        {
            if (controlId != ChooseFolderButton) return 0;
            string folderPath = null;
            // Prefer an actual highlighted directory, otherwise use the folder
            // currently displayed in the native Explorer view.
            IShellItem selection = null;
            if (fileDialog.GetCurrentSelection(out selection) >= 0 && selection != null)
            {
                try {
                    string path = NativePicker.ItemPath(selection);
                    if (Directory.Exists(path)) folderPath = path;
                } finally { Marshal.ReleaseComObject(selection); }
            }
            if (folderPath == null)
            {
                IShellItem folder = null;
                if (fileDialog.GetFolder(out folder) >= 0 && folder != null)
                {
                    try { folderPath = NativePicker.ItemPath(folder); }
                    finally { Marshal.ReleaseComObject(folder); }
                }
            }
            if (!String.IsNullOrEmpty(folderPath) && Directory.Exists(folderPath))
            {
                ChosenFolder = folderPath;
                fileDialog.Close(0);
            }
            return 0;
        }

        public int OnFileOk(IFileDialog dialog) { return 0; }
        public int OnFolderChanging(IFileDialog dialog, IShellItem folder) { return 0; }
        public int OnFolderChange(IFileDialog dialog) { return 0; }
        public int OnSelectionChange(IFileDialog dialog) { return 0; }
        public int OnShareViolation(IFileDialog dialog, IShellItem item, out uint response)
        { response = 0; return 0; }
        public int OnTypeChange(IFileDialog dialog) { return 0; }
        public int OnOverwrite(IFileDialog dialog, IShellItem item, out uint response)
        { response = 0; return 0; }
        public int OnItemSelected(IFileDialogCustomize dialog, uint ctl, uint item) { return 0; }
        public int OnCheckButtonToggled(IFileDialogCustomize dialog, uint ctl, bool value) { return 0; }
        public int OnControlActivating(IFileDialogCustomize dialog, uint ctl) { return 0; }
    }

    public static class NativePicker
    {
        private const uint ChooseFolderButton = 4107;
        private const uint FilesystemOnly = 0x00000040;
        private const uint NoChangeDir = 0x00000008;
        private const uint FileMustExist = 0x00001000;
        private const uint PathMustExist = 0x00000800;
        private const uint FileSystemPath = 0x80058000;
        private const int UserCanceled = unchecked((int)0x800704C7);
        private static readonly Guid DialogClass = new Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7");

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string path,
            IntPtr bindContext, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

        internal static string ItemPath(IShellItem item)
        {
            IntPtr raw = IntPtr.Zero;
            int hr = item.GetDisplayName(FileSystemPath, out raw);
            Marshal.ThrowExceptionForHR(hr);
            try { return Marshal.PtrToStringUni(raw); }
            finally { if (raw != IntPtr.Zero) Marshal.FreeCoTaskMem(raw); }
        }

        private static IFileDialog CreateDialog()
        {
            return (IFileDialog)Activator.CreateInstance(Type.GetTypeFromCLSID(DialogClass));
        }

        private static void Configure(IFileDialog dialog, IFileDialogCustomize custom)
        {
            uint opts;
            Marshal.ThrowExceptionForHR(dialog.GetOptions(out opts));
            Marshal.ThrowExceptionForHR(dialog.SetOptions(opts | FilesystemOnly | NoChangeDir | FileMustExist | PathMustExist));
            var types = new FilterSpec[] {
                new FilterSpec { Name = "Expansion Pack ZIP (*.zip)", Pattern = "*.zip" },
                new FilterSpec { Name = "All Files (*.*)", Pattern = "*.*" }
            };
            Marshal.ThrowExceptionForHR(dialog.SetFileTypes((uint)types.Length, types));
            Marshal.ThrowExceptionForHR(dialog.SetFileTypeIndex(1));
            Marshal.ThrowExceptionForHR(dialog.SetTitle("Choose an NP Expansion Pack ZIP or folder"));
            Marshal.ThrowExceptionForHR(dialog.SetOkButtonLabel("Open ZIP"));
            Marshal.ThrowExceptionForHR(custom.AddPushButton(ChooseFolderButton, "Use This Folder"));

            // A remembered shell location may supersede this default.
            string downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            if (Directory.Exists(downloads))
            {
                Guid iid = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
                IShellItem start = null;
                if (SHCreateItemFromParsingName(downloads, IntPtr.Zero, ref iid, out start) >= 0 && start != null)
                {
                    try { dialog.SetDefaultFolder(start); }
                    finally { Marshal.ReleaseComObject(start); }
                }
            }
        }

        public static string Select(long ownerHandle)
        {
            IFileDialog dialog = CreateDialog();
            try {
                IFileDialogCustomize customize = (IFileDialogCustomize)dialog;
                Configure(dialog, customize);
                var events = new DialogEvents(dialog);
                uint cookie;
                Marshal.ThrowExceptionForHR(dialog.Advise(events, out cookie));
                try {
                    int hr = dialog.Show(new IntPtr(ownerHandle));
                    if (!String.IsNullOrEmpty(events.ChosenFolder)) return events.ChosenFolder;
                    if (hr == UserCanceled) return null;
                    Marshal.ThrowExceptionForHR(hr);
                    IShellItem result = null;
                    Marshal.ThrowExceptionForHR(dialog.GetResult(out result));
                    if (result == null) throw new InvalidOperationException("The picker returned no selected item.");
                    try {
                        string path = ItemPath(result);
                        if (Directory.Exists(path) ||
                            (File.Exists(path) && String.Equals(Path.GetExtension(path), ".zip", StringComparison.OrdinalIgnoreCase)))
                            return path;
                        throw new InvalidOperationException("Choose a ZIP, or use the 'Use This Folder' button.");
                    } finally { Marshal.ReleaseComObject(result); }
                }
                finally { dialog.Unadvise(cookie); GC.KeepAlive(events); }
            }
            finally { Marshal.ReleaseComObject(dialog); }
        }

        // Noninteractive build preflight: construct the native COM dialog,
        // customize it and register events without showing a window.
        public static void SmokeTest()
        {
            IFileDialog dialog = CreateDialog();
            try {
                IFileDialogCustomize custom = (IFileDialogCustomize)dialog;
                Configure(dialog, custom);
                var events = new DialogEvents(dialog);
                uint cookie;
                Marshal.ThrowExceptionForHR(dialog.Advise(events, out cookie));
                try { GC.KeepAlive(events); }
                finally { dialog.Unadvise(cookie); }
            } finally { Marshal.ReleaseComObject(dialog); }
        }
    }
}
'@
try {
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    if ($SmokeTest) {
        [TES3NP.Expansion.NativePicker]::SmokeTest()
        Write-Host 'Unified native Expansion Pack picker COM smoke test passed.'
        exit 0
    }
    if (!$ResultFile) { throw 'Picker result destination was not supplied.' }
    $selected = [TES3NP.Expansion.NativePicker]::Select($OwnerHwnd)
    if ($selected) {
        $selected = [IO.Path]::GetFullPath($selected)
        [IO.File]::WriteAllText($ResultFile, $selected, [Text.UTF8Encoding]::new($false))
    }
    exit 0
}
catch {
    if ($ResultFile) {
        try {
            [IO.File]::WriteAllText(($ResultFile + '.error'),
                $_.Exception.GetBaseException().Message, [Text.UTF8Encoding]::new($false))
        } catch {}
    }
    Write-Host ('Expansion Pack selection failed: ' + $_.Exception.GetBaseException().Message)
    exit 1
}
