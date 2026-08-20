# Generic DECB disk-file library

Include `DECB_Disk_File_Library.asm` in a standalone 6809 project to access a
physical DECB floppy without Disk BASIC's `$0600-$0DFF` workspace. The module
contains its own relocatable state, full-disk granule allocation list, 256-byte
sector buffer, WD17xx driver, and CoCo 1/2/3 NMI handler.

The current build occupies `$07F3` bytes of code and reserves `$018F` bytes of
workspace, for a total address span of `$0982` bytes. `DiskLibInit` clears and
signs the workspace on first use, so it is safe when an assembler treats `RMB`
as uninitialized storage and omits it from the load file.

## LOADM

```asm
        LDX     #Filename       * zero-terminated NAME[.EXT][:0-3]
        LDD     #0              * signed offset added to load and EXEC addresses
        JSR     DiskLibLoadM
        BCS     DiskError       * B contains an error number
        * D now contains the file's EXEC address
```

The extension defaults to `BIN` and the drive defaults to zero. LOADM follows
the complete FAT chain and supports multi-segment files larger than 64K. Each
individual DECB segment still uses the standard 16-bit length and address.

The loaded file must not overwrite this library, its workspace, the active
stack, or currently executing caller before `DiskLibLoadM` returns.

## SAVEM

```asm
        LDX     #Filename       * zero-terminated NAME[.EXT][:0-3]
        LDD     #SaveStart
        LDU     #SaveEnd        * inclusive
        LDY     #ExecAddress
        JSR     DiskLibSaveM
        BCS     DiskError       * B contains an error number
```

SAVEM writes one standard DECB machine-language segment. It checks the FAT,
uses only free granules, writes all data before committing the FAT, and
publishes the directory entry last. Existing files are not overwritten. The
shared allocation list can represent all 68 granules on a disk.

## Sequential byte input

```asm
        LDX     #Filename
        JSR     DiskLibOpenRead
        BCS     DiskError
ReadNext:
        JSR     DiskLibReadByte         * success: next byte is in A
        BCC     HaveByte
        CMPB    #DiskErrorEndOfFile
        BNE     DiskError
        JSR     DiskLibCloseRead
        BRA     ReadFinished
HaveByte:
        * process A here
        BRA     ReadNext
```

`DiskLibReadByte` follows the FAT chain and honors the exact byte count stored
for the final sector. It therefore does not return the sector's unused padding.
End of file returns carry set with B equal to 12; this is a normal condition and
the input stream remains open until `DiskLibCloseRead` is called.

## Sequential byte output

```asm
        LDX     #Filename
        CLRA                            * 0=binary; nonzero=ASCII
        LDB     #1                      * DECB file type 0 through 3
        JSR     DiskLibOpenWrite
        BCS     DiskError

        LDB     #$41                    * append one byte
        JSR     DiskLibWriteByte
        BCS     DiskError

        JSR     DiskLibCloseWrite       * flush and publish the file
        BCS     DiskError
```

The writer refuses to overwrite an existing file. Data sectors are written as
bytes fill them, but the FAT and directory are not changed until
`DiskLibCloseWrite` succeeds. A failed or abandoned write therefore does not
publish a partial file. At least one byte must be written before closing.

Only one sequential stream may be open at a time. LOADM, SAVEM, and the file
existence check also return error 16 while a stream is open because those calls
share the sector buffer.

## NMI ownership

Every public operation calls `DiskLibInit` automatically. The first call saves
the existing three-byte NMI trampoline and installs `DiskLibNMI` at `$0109` on
a CoCo 1/2 or `$FEFD` on a CoCo 3. Call `DiskLibShutdown` when disk operations
are finished to restore those bytes. A CoCo 3 project must enable GIME vector
RAM before using the library.

The WD17xx transfers run at normal CPU speed and leave the machine at normal
speed. A project that normally runs at high speed should restore its preferred
speed after the call.

## Return convention

Carry clear means success. Carry set means failure, with B containing:

| B | Meaning |
|---:|---|
| 1 | File not found |
| 2 | Disk write-protected |
| 3 | Disk input/output error |
| 4 | Not a DECB machine-language file or bad FAT chain |
| 5 | File already exists |
| 6 | Disk full |
| 7 | Directory full |
| 8 | Invalid SAVEM address range |
| 9 | SAVEM range overlaps the library workspace |
| 10 | Invalid or empty filename |
| 11 | Invalid drive suffix |
| 12 | End of sequential input file |
| 13 | Cannot close an empty output file |
| 14 | Required input/output stream is not open |
| 15 | Invalid DECB output file type (must be 0-3) |
| 16 | A sequential stream is already open |

The routines may change all 6809 registers. LOADM returns its EXEC address in
D. The library never prints an error or halts the caller.

Assembled callers and listings, including byte-reader and byte-writer examples,
are under `Tests/Generic_Disk_Library`.
