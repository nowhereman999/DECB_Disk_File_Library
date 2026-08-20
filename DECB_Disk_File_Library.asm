************************************************************************
* Generic DECB floppy-disk and sequential-file library for 6809 projects
*
* Public entry points:
*   DiskLibLoadM       X -> zero-terminated filename, D = signed offset
*                      Returns C clear and D = EXEC address on success.
*   DiskLibSaveM       X -> zero-terminated filename, D = start address,
*                      U = inclusive end, Y = EXEC address.
*                      Returns C clear on success.
*   DiskLibFileExists  X -> zero-terminated filename.
*                      Returns C clear if found, C set/B=1 if absent.
*   DiskLibOpenRead    X -> zero-terminated filename.
*   DiskLibReadByte    Returns C clear/A=next byte, or C set/B=12 at EOF.
*   DiskLibCloseRead   Close the current input file.
*   DiskLibOpenWrite   X -> zero-terminated filename, B=DECB type (0-3),
*                      A=0 for binary or nonzero for ASCII.
*   DiskLibWriteByte   B=byte to append. Returns C clear on success.
*   DiskLibCloseWrite  Flush and publish the current output file.
*   DiskLibInit        Install the CoCo 1/2 or CoCo 3 NMI hook.
*   DiskLibMotorOff    Immediately turn off the motor and deselect drives.
*   DiskLibShutdown    Restore the three bytes replaced by DiskLibInit.
*
* Filenames use NAME.EXT or NAME.EXT:drive. The extension defaults to BIN and
* drive defaults to zero. Drive may be 0 through 3. All errors return with
* carry set and an error number in B; this module never prints or halts.
*
* The code and all workspace are relocatable. Include this file where the
* assembler's current location is safe. It reserves one 256-byte sector buffer
* plus compact state; it does not use Disk BASIC's $0600-$0DFF workspace.
*
* DiskLibInit recognizes the standard CoCo 3 reset vector ($8C1B), selecting
* the NMI trampoline at $FEFD; otherwise it uses the CoCo 1/2 trampoline at
* $0109. A CoCo 3 project must have GIME vector RAM enabled before calling it.
* Disk transfers run at normal speed and leave the machine at normal speed.
************************************************************************

DSKREG          EQU     $FF40
FDCREG          EQU     $FF48
SECLEN          EQU     256
GRANMX          EQU     68
DIRLEN          EQU     32
MAXSAVEGRAN     EQU     68

DiskErrorFileNotFound     EQU  1
DiskErrorWriteProtected   EQU  2
DiskErrorIOError          EQU  3
DiskErrorNotMLFileType    EQU  4
DiskErrorFileExists       EQU  5
DiskErrorDiskFull         EQU  6
DiskErrorDirectoryFull    EQU  7
DiskErrorBadRange         EQU  8
DiskErrorWorkspaceOverlap EQU  9
DiskErrorBadFilename      EQU  10
DiskErrorBadDrive         EQU  11
DiskErrorEndOfFile        EQU  12
DiskErrorEmptyFile        EQU  13
DiskErrorFileNotOpen      EQU  14
DiskErrorBadFileType      EQU  15
DiskErrorStreamOpen       EQU  16

DIRTYP          EQU     11
DIRASC          EQU     12
DIRGRN          EQU     13

* High-level APIs save S so errors deep in the controller can unwind safely.
DiskLibLoadM:
        LBSR    DiskLibInit
        STS     DiskApiStack
        TST     DiskStreamMode
        LBNE    DiskStreamAlreadyOpen
        STD     DiskLoadOffset
        LBSR    DiskFormatFilenameX
        LBCS    DiskError
        LDU     #DNAMBF
        JSR     OpenFileU
        LBCS    DiskError
        JSR     InitFile
        JSR     DiskLOADM
        LDD     DiskLoadExec
        JSR     DiskLibMotorOff
        ANDCC   #$FE
        RTS

DiskLibSaveM:
        LBSR    DiskLibInit
        STS     DiskApiStack
        TST     DiskStreamMode
        LBNE    DiskStreamAlreadyOpen
        STD     DiskSaveStart
        STU     DiskSaveEnd
        STY     DiskSaveExec
        LBSR    DiskFormatFilenameX
        LBCS    DiskError
        JSR     DiskSAVEM
        JSR     DiskLibMotorOff
        CLRB
        ANDCC   #$FE
        RTS

DiskLibFileExists:
        LBSR    DiskLibInit
        STS     DiskApiStack
        TST     DiskStreamMode
        LBNE    DiskStreamAlreadyOpen
        LBSR    DiskFormatFilenameX
        LBCS    DiskError
        LDU     #DNAMBF
        JSR     OpenFileU
        BCS     DiskLibExistsAbsent
        JSR     DiskLibMotorOff
        CLRB
        ANDCC   #$FE
        RTS
DiskLibExistsAbsent:
        * OpenFileU already returns B=DiskErrorFileNotFound.
        JSR     DiskLibMotorOff
        ORCC    #1
        RTS

* Open an existing DECB file for exact, sequential byte reads.
DiskLibOpenRead:
        LBSR    DiskLibInit
        STS     DiskApiStack
        TST     DiskStreamMode
        LBNE    DiskStreamAlreadyOpen
        LBSR    DiskFormatFilenameX
        LBCS    DiskError
        LDU     #DNAMBF
        JSR     OpenFileU
        LBCS    DiskError
        JSR     InitFile
        LDA     #1
        STA     DiskStreamMode
        CLRB
        ANDCC   #$FE
        RTS

DiskLibReadByte:
        STS     DiskApiStack
        LDA     DiskStreamMode
        CMPA    #1
        LBNE    DiskFileNotOpen
        JSR     DiskReadByteA
        ANDCC   #$FE
        RTS

DiskLibCloseRead:
        LDA     DiskStreamMode
        CMPA    #1
        LBNE    DiskFileNotOpenDirect
        CLR     DiskStreamMode
        JSR     DiskLibMotorOff
        CLRB
        ANDCC   #$FE
        RTS

* Create a new sequential file. Existing files are never overwritten.
DiskLibOpenWrite:
        LBSR    DiskLibInit
        STS     DiskApiStack
        TST     DiskStreamMode
        LBNE    DiskStreamAlreadyOpen
        CMPB    #3
        LBHI    DiskBadFileType
        STB     DiskOutputFileType
        TSTA
        BEQ     >
        LDA     #$FF
!       STA     DiskOutputASCII
        LBSR    DiskFormatFilenameX
        LBCS    DiskError
        JSR     DiskWriterBegin
        LDA     #2
        STA     DiskStreamMode
        CLRB
        ANDCC   #$FE
        RTS

DiskLibWriteByte:
        STS     DiskApiStack
        LDA     DiskStreamMode
        CMPA    #2
        LBNE    DiskFileNotOpen
        JSR     DiskWriteByteB
        ANDCC   #$FE
        RTS

DiskLibCloseWrite:
        STS     DiskApiStack
        LDA     DiskStreamMode
        CMPA    #2
        LBNE    DiskFileNotOpen
        TST     DiskWriteAny
        LBEQ    DiskEmptyOutputFile
        JSR     DiskFinishWriteBuffer
        JSR     DiskWriterCommit
        CLR     DiskStreamMode
        JSR     DiskLibMotorOff
        CLRB
        ANDCC   #$FE
        RTS

DiskFileNotOpen:
DiskFileNotOpenDirect:
        LDB     #DiskErrorFileNotOpen
        ORCC    #1
        RTS
DiskBadFileType:
        LDB     #DiskErrorBadFileType
        ORCC    #1
        RTS
DiskStreamAlreadyOpen:
        LDB     #DiskErrorStreamOpen
        ORCC    #1
        RTS

* Install the NMI trampoline once, preserving the previous three bytes.
DiskLibInit:
        PSHS    CC,D,X,Y
        LDD     DiskInitMagic
        CMPD    #$444C                  * "DL"
        BNE     DiskLibClearState
        LDD     DiskInitMagic+2
        CMPD    #$4942                  * "IB"
        BEQ     DiskLibStateReady
DiskLibClearState:
        LDX     #DiskWorkspaceStart
        CLRA
!       STA     ,X+
        CMPX    #DiskWorkspaceEnd
        BNE     <
        LDD     #$444C
        STD     DiskInitMagic
        LDD     #$4942
        STD     DiskInitMagic+2
DiskLibStateReady:
        TST     DiskNMIInstalled
        BNE     DiskLibInitDone
        LDX     >$FFFE                  ; Test for CoCo 1/2 or CoCo 3
        CMPX    #$8C1B
        BNE     DiskLibUseCoCo12NMI
        LDY     #$FEFD
        BRA     DiskLibSaveNMI
DiskLibUseCoCo12NMI:
        LDY     #$0109
DiskLibSaveNMI:
        STY     DiskNMIVector
        LDX     #DiskSavedNMI
        LDA     ,Y
        STA     ,X+
        LDD     1,Y
        STD     ,X
        ORCC    #$50
        LDA     #$7E
        STA     ,Y
        LDD     #DiskLibNMI
        STD     1,Y
        COM     DiskNMIInstalled
DiskLibInitDone:
        * PULS restores the caller's original IRQ/FIRQ mask state.
        PULS    CC,D,X,Y,PC

DiskLibShutdown:
        PSHS    CC,D,X,Y
        TST     DiskNMIInstalled
        BEQ     DiskLibShutdownDone
        JSR     DiskLibMotorOff
        ORCC    #$50
        LDY     DiskNMIVector
        LDX     #DiskSavedNMI
        LDA     ,X+
        STA     ,Y
        LDD     ,X
        STD     1,Y
        CLR     DiskNMIInstalled
DiskLibShutdownDone:
        * PULS restores the caller's original IRQ/FIRQ mask state.
        PULS    CC,D,X,Y,PC

* Turn off the motor and all drive selects without changing caller registers
* or condition codes. This is also safe to call explicitly after disk use.
DiskLibMotorOff:
        PSHS    CC,A
        LDA     DRGRAM
        ANDA    #$B0
        STA     DRGRAM
        STA     DSKREG
        CLR     RDYTMR
        PULS    CC,A,PC

DiskLibNMI:
        LDA     NMIFLG
        BEQ     DiskLibUnexpectedNMI
        LDX     DNMIVC
        STX     10,S
        CLR     NMIFLG
        RTI
DiskLibUnexpectedNMI:
        LDA     DiskSavedNMI
        CMPA    #$7E
        BNE     DiskLibNMIReturn
        JMP     [DiskSavedNMI+1]
DiskLibNMIReturn:
        RTI

* Convert an ASCIIZ filename at X into the DECB 8.3 name at DNAMBF.
* A missing extension becomes BIN; a trailing :0 through :3 selects drive.
DiskFormatFilenameX:
        CLR     DCDRV
        STX     DiskNameSource
        LDU     #DNAMBF
        LDA     #' '
        LDB     #11
!       STA     ,U+
        DECB
        BNE     <
        LDX     DiskNameSource
        LDU     #DNAMBF
        LDB     #8
DiskCopyFilename:
        LDA     ,X
        BEQ     DiskFilenameDefaultExtension
        CMPA    #'.'
        BEQ     DiskFilenameFoundExtension
        CMPA    #':'
        BEQ     DiskFilenameDefaultExtension
        CMPA    #'a'
        BLO     >
        CMPA    #'z'
        BHI     >
        SUBA    #$20
!
        STA     ,U+
        LEAX    1,X
        DECB
        BNE     DiskCopyFilename
DiskFilenameFindDelimiter:
        LDA     ,X+
        BEQ     DiskFilenameDefaultExtension
        CMPA    #'.'
        BEQ     DiskFilenameExtensionReady
        CMPA    #':'
        BNE     DiskFilenameFindDelimiter
        LEAX    -1,X
        BRA     DiskFilenameDefaultExtension
DiskFilenameFoundExtension:
        LEAX    1,X
DiskFilenameExtensionReady:
        LDU     #DNAMBF+8
        LDB     #3
DiskFilenameCopyExtension:
        LDA     ,X
        BEQ     DiskFilenameDone
        CMPA    #':'
        BEQ     DiskFilenameDrive
        CMPA    #'a'
        BLO     >
        CMPA    #'z'
        BHI     >
        SUBA    #$20
!
        STA     ,U+
        LEAX    1,X
        DECB
        BNE     DiskFilenameCopyExtension
DiskFilenameFindDrive:
        LDA     ,X+
        BEQ     DiskFilenameDone
        CMPA    #':'
        BNE     DiskFilenameFindDrive
        LEAX    -1,X
        BRA     DiskFilenameDrive
DiskFilenameDefaultExtension:
        LDD     #'B'*256+'I'
        STD     DNAMBF+8
        LDA     #'N'
        STA     DNAMBF+10
DiskFilenameFindSuffix:
        LDA     ,X+
        BEQ     DiskFilenameDone
        CMPA    #':'
        BNE     DiskFilenameFindSuffix
        LEAX    -1,X
DiskFilenameDrive:
        LEAX    1,X
        LDA     ,X+
        SUBA    #'0'
        CMPA    #3
        BHI     DiskFilenameBadDrive
        TST     ,X
        BNE     DiskFilenameBadDrive
        STA     DCDRV
DiskFilenameDone:
        LDA     DNAMBF
        CMPA    #' '
        BEQ     DiskFilenameBad
        CLRB
        ANDCC   #$FE
        RTS
DiskFilenameBad:
        LDB     #DiskErrorBadFilename
        ORCC    #1
        RTS
DiskFilenameBadDrive:
        LDB     #DiskErrorBadDrive
        ORCC    #1
        RTS

; Put the controller in a known state without relying on Disk BASIC RAM.
DiskBegin:
        STA     >$FFD8                  ; normal speed for WD17xx timing
        CLR     DRGRAM
        CLR     NMIFLG
        CLR     DCSTA
        CLR     RDYTMR
        CLR     DiskTrackImage
        CLR     DCOPC
        JSR     DSKCON                  ; restore selected drive to track zero
        TST     DCSTA
        LBNE    DiskIOError
        RTS

; Search directory for the name at U. Remember first reusable slot for SAVEM.
; C clear/X=entry if found; C set if absent. FreeDirSec=$FF means full.
OpenFileU:
        STU     DiskSearchName
        JSR     DiskBegin
        LDU     DiskSearchName
        LDA     #$FF
        STA     DiskFreeDirSec
        LDA     #3
        STA     DiskDirSector
DiskScanNextSector:
        LDA     #17
        LDB     DiskDirSector
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        LDX     #DiskBuffer
        CLRA                            ; byte offset in directory sector
DiskScanNextEntry:
        LDB     ,X
        BEQ     DiskRememberFreeEntry
        CMPB    #$FF
        BEQ     DiskRememberLastFree
        PSHS    A,X,U
        LDB     #11
DiskCompareName:
        LDA     ,X+
        CMPA    ,U+
        BNE     DiskNameMismatch
        DECB
        BNE     DiskCompareName
        PULS    A,X,U
        ANDCC   #$FE
        RTS
DiskNameMismatch:
        PULS    A,X,U
        BRA     DiskAdvanceDirEntry
DiskRememberLastFree:
        BSR     DiskRememberFree
        LDB     #DiskErrorFileNotFound
        ORCC    #1
        RTS
DiskRememberFreeEntry:
        BSR     DiskRememberFree
DiskAdvanceDirEntry:
        LEAX    DIRLEN,X
        ADDA    #DIRLEN
        BNE     DiskScanNextEntry       ; wraps after eight entries
        INC     DiskDirSector
        LDA     DiskDirSector
        CMPA    #12
        BLO     DiskScanNextSector
        LDB     #DiskErrorFileNotFound
        ORCC    #1
        RTS
DiskRememberFree:
        PSHS    A
        LDA     DiskFreeDirSec
        CMPA    #$FF
        BNE     >
        LDA     DiskDirSector
        STA     DiskFreeDirSec
        PULS    A
        STA     DiskFreeDirOff
        RTS
!       PULS    A,PC

; Initialize found directory entry for sequential file reads.
InitFile:
        LDD     14,X                    ; exact byte count in final sector
        CMPD    #SECLEN
        LBHI    DiskBadMLFile
        STD     DiskReadLastLen
        LDA     DIRASC,X
        ANDA    #$F0
        ORA     DIRTYP,X
        STA     DiskFileType
        LDA     DIRGRN,X
        STA     DiskCurrentGran
        JSR     DiskLoadPrepareGranule
        LBCS    DiskBadMLFile
        RTS

; Reuse DiskBuffer for the FAT lookup, then load first data sector.
DiskLoadPrepareGranule:
        LDD     #17*$100+2
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        LDA     DiskCurrentGran
        CMPA    #GRANMX
        BHS     DiskLoadBadChain
        LDB     A,X
        STB     DiskNextGran
        CLR     DiskLastGran
        CMPB    #$C0
        BLO     DiskLoadFullGranule
        COM     DiskLastGran
        ANDB    #$3F
        BEQ     DiskLoadBadChain
        CMPB    #9
        BHI     DiskLoadBadChain
        PSHS    B
        JSR     DiskMapCurrentGranule
        ADDB    ,S+
        STB     DiskGranuleEnd
        BRA     DiskLoadFirstSector
DiskLoadFullGranule:
        CMPB    #GRANMX
        BHS     DiskLoadBadChain
        JSR     DiskMapCurrentGranule
        ADDB    #9
        STB     DiskGranuleEnd
DiskLoadFirstSector:
        LDD     DCTRK
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        STX     DiskBufferPtr
        BSR     DiskSetReadLimit
        ANDCC   #$FE
        RTS
DiskLoadBadChain:
        ORCC    #1
        RTS

; Set the exclusive byte limit for the sector currently in DiskBuffer.
; A zero final-sector length is treated as 256 for disk compatibility.
DiskSetReadLimit:
        PSHS    D
        LDD     #DiskBuffer+SECLEN
        TST     DiskLastGran
        BEQ     DiskStoreReadLimit
        LDA     DSEC
        INCA
        CMPA    DiskGranuleEnd
        BNE     DiskStoreReadLimit
        LDD     DiskReadLastLen
        BNE     >
        LDD     #SECLEN
!       ADDD    #DiskBuffer
DiskStoreReadLimit:
        STD     DiskReadLimit
        PULS    D,PC

; Map granule 0-67 to track/starting sector, skipping directory track 17.
DiskMapCurrentGranule:
        LDA     DiskCurrentGran
        LDB     #1
        BITA    #1
        BEQ     >
        LDB     #10
!       CMPA    #34
        BLO     >
        ADDA    #2
!       LSRA
        STA     DCTRK
        STB     DSEC
        RTS

; LOADM reader. DiskLoadOffset is added to every load and EXEC address.
; There is deliberately no aggregate 16-bit file-length counter: every DECB
; segment has its own 16-bit length/address and parsing continues through the
; complete FAT chain until the postamble. This permits files larger than 64K,
; including CoCo 3 files which alternate a write to $FFA0-$FFA7 with an 8K
; data segment in the newly mapped logical window. Use offset zero for those
; bank-selector segments so the $FFAx destination is not relocated.
DiskLOADM:
        LDA     DiskFileType
        CMPA    #$02
        LBNE    DiskBadMLFile
DiskGetMLBlock:
        BSR     DiskReadByteA
        TSTA
        BEQ     DiskDoPreamble
        CMPA    #$FF
        LBNE    DiskBadMLFile
        BSR     DiskReadWordD
        CMPD    #0
        BNE     DiskBadMLFile
        BSR     DiskReadWordD
        ADDD    DiskLoadOffset
        STD     DiskLoadExec
        CLR     >$FFD8                  ; leave the machine at normal speed
        RTS
DiskDoPreamble:
        BSR     DiskReadWordD
        TFR     D,X
        BSR     DiskReadWordD
        ADDD    DiskLoadOffset
        TFR     D,U
!       BSR     DiskReadByteA
        STA     ,U+
        LEAX    -1,X
        BNE     <                       ; X=0 represents 65536 bytes
        BRA     DiskGetMLBlock
DiskReadWordD:
        BSR     DiskReadByteA
        TFR     A,B
        BSR     DiskReadByteA
        EXG     A,B
        RTS
DiskReadByteA:
        PSHS    B,X,U
        LDX     DiskBufferPtr
        CMPX    DiskReadLimit
        BNE     DiskReadHaveByte
        INC     DSEC
        LDB     DSEC
        CMPB    DiskGranuleEnd
        BLO     DiskReadNextSector
        TST     DiskLastGran
        BNE     DiskReadPastEOF
        LDA     DiskNextGran
        STA     DiskCurrentGran
        JSR     DiskLoadPrepareGranule
        BCS     DiskReadPastEOF
        LDX     DiskBufferPtr
        BRA     DiskReadHaveByte
DiskReadNextSector:
        LDA     DCTRK
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        STX     DiskBufferPtr
        LBSR    DiskSetReadLimit
        LDX     DiskBufferPtr
DiskReadHaveByte:
        LDA     ,X+
        STX     DiskBufferPtr
        PULS    B,X,U,PC
DiskReadPastEOF:
        PULS    B,X,U
        LDA     DiskStreamMode
        CMPA    #1
        BNE     DiskBadMLFile
        LDS     DiskApiStack
        LDB     #DiskErrorEndOfFile
        ORCC    #1
        RTS
DiskBadMLFile:
        LDB     #DiskErrorNotMLFileType
        JMP     DiskError

; SAVEM "NAME.BIN[:drive]",start,end,exec
; Existing files are not overwritten, matching Disk BASIC's FE error.
DiskSAVEM:
        LDD     DiskSaveEnd
        CMPD    DiskSaveStart
        LBLO    DiskSaveRangeError
        CMPD    #DiskWorkspaceStart
        BLO     DiskSaveRangeIsSafe
        LDD     DiskSaveStart
        CMPD    #DiskWorkspaceEnd
        LBLO    DiskSaveWorkspaceError
DiskSaveRangeIsSafe:
        LDA     #2                      ; DECB machine-language, binary
        STA     DiskOutputFileType
        CLR     DiskOutputASCII
        JSR     DiskWriterBegin

; Preamble: 00, length, load address.
        CLRB
        JSR     DiskWriteByteB
        LDD     DiskSaveEnd
        SUBD    DiskSaveStart
        ADDD    #1
        JSR     DiskWriteWordD
        LDD     DiskSaveStart
        JSR     DiskWriteWordD

; Save inclusive range. Compare before increment so end=$FFFF works.
        LDU     DiskSaveStart
DiskSaveDataLoop:
        LDB     ,U
        JSR     DiskWriteByteB
        CMPU    DiskSaveEnd
        BEQ     DiskSaveDataDone
        LEAU    1,U
        BRA     DiskSaveDataLoop
DiskSaveDataDone:
        LDB     #$FF
        JSR     DiskWriteByteB
        CLRB
        JSR     DiskWriteByteB
        JSR     DiskWriteByteB
        LDD     DiskSaveExec
        JSR     DiskWriteWordD
        JSR     DiskFinishWriteBuffer
        JSR     DiskWriterCommit
        RTS

; Prepare a new file and its in-memory free-granule list. The on-disk FAT and
; directory remain unchanged until DiskWriterCommit is called.
DiskWriterBegin:
        LDU     #DNAMBF
        JSR     OpenFileU
        LBCC    DiskSaveFileExists
        LDA     DiskFreeDirSec
        CMPA    #$FF
        LBEQ    DiskSaveDirectoryFull

; Gather free granules without modifying the disk FAT.
        LDD     #17*$100+2
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        LDX     #DiskBuffer
        LDU     #DiskGranuleList
        CLR     DiskSaveListCnt
        CLRA
DiskSaveFindFree:
        LDB     ,X+
        CMPB    #$FF
        BNE     DiskSaveNotFree
        LDB     DiskSaveListCnt
        CMPB    #MAXSAVEGRAN
        BHS     DiskSaveFreeListDone
        STA     ,U+
        INC     DiskSaveListCnt
DiskSaveNotFree:
        INCA
        CMPA    #GRANMX
        BLO     DiskSaveFindFree
DiskSaveFreeListDone:
        TST     DiskSaveListCnt
        LBEQ    DiskSaveDiskFull
        CLR     DiskSaveListPos
        CLR     DiskSaveSectors
        LDD     #DiskBuffer
        STD     DiskBufferPtr
        LDA     DiskGranuleList
        STA     DiskCurrentGran
        JSR     DiskMapCurrentGranule
        CLR     DiskWriteAny
        RTS

; Commit FAT after every data sector has succeeded.
DiskWriterCommit:
        LDD     #17*$100+2
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        LDU     #DiskBuffer
        LDX     #DiskGranuleList
        LDB     DiskSaveListPos
        BEQ     DiskSaveMarkLastGranule
DiskSaveLinkGranules:
        LDA     ,X+
        PSHS    B
        LDB     ,X
        STB     A,U
        PULS    B
        DECB
        BNE     DiskSaveLinkGranules
DiskSaveMarkLastGranule:
        LDA     ,X
        LDB     DiskSaveSectors
        ORB     #$C0
        STB     A,U
        LDD     #17*$100+2
        LDX     #DiskBuffer
        JSR     WriteSectorDFromX

; Publish directory entry last.
        LDA     #17
        LDB     DiskFreeDirSec
        LDX     #DiskBuffer
        JSR     ReadSectorDtoX
        LDX     #DiskBuffer
        LDB     DiskFreeDirOff
        ABX
        PSHS    X
        LDB     #DIRLEN
        CLRA
!       STA     ,X+
        DECB
        BNE     <
        PULS    X
        LDU     #DNAMBF
        LDB     #11
!       LDA     ,U+
        STA     ,X+
        DECB
        BNE     <
        LDA     DiskOutputFileType
        STA     ,X+
        LDA     DiskOutputASCII
        STA     ,X+
        LDA     DiskGranuleList
        STA     ,X+
        LDD     DiskSaveLastLen
        STD     ,X
        LDA     #17
        LDB     DiskFreeDirSec
        LDX     #DiskBuffer
        JSR     WriteSectorDFromX
        CLR     >$FFD8                  ; leave the machine at normal speed
        RTS

DiskWriteWordD:
        STD     DiskSaveWord
        LDB     DiskSaveWord
        BSR     DiskWriteByteB
        LDB     DiskSaveWord+1
        BRA     DiskWriteByteB

; Append B. Select another granule only when another byte is actually needed.
DiskWriteByteB:
        PSHS    A,X
        LDX     DiskBufferPtr
        CMPX    #DiskBuffer
        BNE     DiskWriteStoreByte
        LDA     DiskSaveSectors
        CMPA    #9
        BNE     DiskWriteStoreByte
        PSHS    B                       ; preserve pending data byte
        INC     DiskSaveListPos
        LDA     DiskSaveListPos
        CMPA    DiskSaveListCnt
        BHS     DiskWriteOutOfSpaceSavedB
        LDX     #DiskGranuleList
        LDA     A,X
        STA     DiskCurrentGran
        CLR     DiskSaveSectors
        JSR     DiskMapCurrentGranule
        LDX     #DiskBuffer
        PULS    B                       ; restore pending data byte
DiskWriteStoreByte:
        LDA     #$FF
        STA     DiskWriteAny
        STB     ,X+
        STX     DiskBufferPtr
        CMPX    #DiskBuffer+SECLEN
        BNE     DiskWriteByteDone
        BSR     DiskFlushWriteSector
DiskWriteByteDone:
        PULS    A,X,PC
DiskWriteOutOfSpace:
        PULS    A,X
        LBRA    DiskSaveDiskFull
DiskWriteOutOfSpaceSavedB:
        LEAS    1,S                     ; discard saved pending data byte
        BRA     DiskWriteOutOfSpace

DiskFlushWriteSector:
        PSHS    D,X
        LDD     DCTRK
        LDX     #DiskBuffer
        JSR     WriteSectorDFromX
        INC     DSEC
        INC     DiskSaveSectors
        LDD     #DiskBuffer
        STD     DiskBufferPtr
        PULS    D,X,PC

DiskFinishWriteBuffer:
        LDX     DiskBufferPtr
        CMPX    #DiskBuffer
        BEQ     DiskLastSectorWasFull
        TFR     X,D
        SUBD    #DiskBuffer
        STD     DiskSaveLastLen
        CLRA
!       STA     ,X+
        CMPX    #DiskBuffer+SECLEN
        BNE     <
        BSR     DiskFlushWriteSector
        RTS
DiskLastSectorWasFull:
        LDD     #SECLEN
        STD     DiskSaveLastLen
        RTS

DiskSaveFileExists:
        LDB     #DiskErrorFileExists
        LBRA    DiskError
DiskSaveDiskFull:
        LDB     #DiskErrorDiskFull
        LBRA    DiskError
DiskSaveDirectoryFull:
        LDB     #DiskErrorDirectoryFull
        LBRA    DiskError
DiskSaveRangeError:
        LDB     #DiskErrorBadRange
        LBRA    DiskError
DiskSaveWorkspaceError:
        LDB     #DiskErrorWorkspaceOverlap
        LBRA    DiskError
DiskEmptyOutputFile:
        LDB     #DiskErrorEmptyFile
        LBRA    DiskError

; Sector I/O wrappers.
WriteSectorDFromX:
        PSHS    A
        LDA     #3
        STA     DCOPC
        PULS    A
        BRA     DiskUpdateLocation
ReadSectorDtoX:
        PSHS    A
        LDA     #2
        STA     DCOPC
        PULS    A
DiskUpdateLocation:
        STD     DCTRK
        STX     DCBPT
        BSR     DSKCON
        TST     DCSTA
        BEQ     >
        LDA     DCSTA
        LDB     #DiskErrorWriteProtected
        BITA    #$40
        LBNE    DiskError
DiskIOError:
        LDB     #DiskErrorIOError
        LBRA    DiskError
!       RTS

; Standalone WD17xx restore/read/write driver.
DSKCON:
        * Preserve the caller's complete condition code, including its IRQ and
        * FIRQ masks.  Sector transfers mask both until the FDC NMI completes.
        PSHS    U,Y,X,B,A,CC
        LDA     #5
        PSHS    A
DiskCommandRetry:
        CLR     RDYTMR
        LDB     DCDRV
        LDX     #DiskDriveMasks
        LDA     DRGRAM
        ANDA    #$A8
        ORA     B,X
        ORA     #$20                    ; double density
        LDB     DCTRK
        CMPB    #22
        BLO     >
        ORA     #$10                    ; write precompensation
!       TFR     A,B
        ORA     #$08
        STA     DRGRAM
        STA     DSKREG
        BITB    #$08
        BNE     DiskMotorReady
        LDX     #0
!       LEAX    -1,X
        BNE     <
        LDX     #0
!       LEAX    -1,X
        BNE     <
DiskMotorReady:
        BSR     DiskWaitNotBusy
        BNE     DiskCommandResult
        CLR     DCSTA
        LDX     #DiskCommandVectors
        LDB     DCOPC
        ASLB
        JSR     [B,X]
DiskCommandResult:
        PULS    A
        LDB     DCSTA
        BEQ     DiskCommandDone
        DECA
        BEQ     DiskCommandDone
        PSHS    A
        BSR     DiskRestore
        BNE     DiskCommandResult
        BRA     DiskCommandRetry
DiskCommandDone:
        LDA     #120
        STA     RDYTMR
        PULS    CC,A,B,X,Y,U,PC

DiskRestore:
        CLR     DiskTrackImage
        LDA     #$03
        STA     FDCREG
        EXG     A,A
        EXG     A,A
        BSR     DiskWaitNotBusy
        BSR     DiskMediumDelay
        ANDA    #$10
        STA     DCSTA
DiskNoOperation:
        RTS
DiskWaitNotBusy:
        LDX     #0
!       LEAX    -1,X
        BEQ     DiskForceInterrupt
        LDA     FDCREG
        BITA    #1
        BNE     <
        RTS
DiskForceInterrupt:
        LDA     #$D0
        STA     FDCREG
        EXG     A,A
        EXG     A,A
        LDA     FDCREG
        LDA     #$80
        STA     DCSTA
        RTS
DiskMediumDelay:
        LDX     #8750
!       LEAX    -1,X
        BNE     <
        RTS

DiskReadSectorCommand:
        LDA     #$80
        BRA     DiskStartSectorCommand
DiskWriteSectorCommand:
        LDA     #$A0
DiskStartSectorCommand:
        PSHS    A
        LDB     DiskTrackImage
        STB     FDCREG+1
        CMPB    DCTRK
        BEQ     DiskHeadPositioned
        LDA     DCTRK
        STA     FDCREG+3
        STA     DiskTrackImage
        LDA     #$17
        STA     FDCREG
        EXG     A,A
        EXG     A,A
        BSR     DiskWaitNotBusy
        BNE     DiskSeekFailed
        BSR     DiskMediumDelay
        ANDA    #$18
        BEQ     DiskHeadPositioned
        STA     DCSTA
DiskSeekFailed:
        PULS    A,PC
DiskHeadPositioned:
        LDA     DSEC
        STA     FDCREG+2
        LDX     #DiskSectorComplete
        STX     DNMIVC
        LDX     DCBPT
        LDA     FDCREG
        LDA     DRGRAM
        ORA     #$80
        PULS    B
        LDY     #0
        LDU     #FDCREG
        COM     NMIFLG
        ORCC    #$50
        STB     FDCREG
        EXG     A,A
        EXG     A,A
        CMPB    #$80
        BEQ     DiskWaitReadDRQ
        LDB     #2
DiskWaitWriteDRQ:
        BITB    ,U
        BNE     DiskWriteDataByte
        LEAY    -1,Y
        BNE     DiskWaitWriteDRQ
        BRA     DiskTransferTimeout
DiskWriteDataByte:
        LDB     ,X+
        STB     FDCREG+3
        STA     DSKREG
        BRA     DiskWriteDataByte
DiskWaitReadDRQ:
        LDB     #2
!       BITB    ,U
        BNE     DiskReadDataByte
        LEAY    -1,Y
        BNE     <
DiskTransferTimeout:
        CLR     NMIFLG
        JMP     DiskForceInterrupt
DiskReadDataByte:
        LDB     FDCREG+3
        STB     ,X+
        STA     DSKREG
        BRA     DiskReadDataByte

; DiskLibNMI replaces the stacked return PC with this completion routine.
DiskSectorComplete:
        LDA     FDCREG
        ANDA    #$7C
        STA     DCSTA
        RTS

DiskCommandVectors:
        FDB     DiskRestore
        FDB     DiskNoOperation
        FDB     DiskReadSectorCommand
        FDB     DiskWriteSectorCommand
DiskDriveMasks:
        FCB     1,2,4,$40

; Return any deep error to the saved high-level API stack frame.
DiskError:
        CLR     DiskStreamMode
        LDS     DiskApiStack
        JSR     DiskLibMotorOff
        ORCC    #1
        RTS

************************************************************************
* Relocatable state and one-sector buffer.
************************************************************************
DiskWorkspaceStart:
DCOPC:             RMB 1       * 0=restore, 2=read, 3=write
DCDRV:             RMB 1       * drive 0-3
DCTRK:             RMB 1
DSEC:              RMB 1
DCBPT:             RMB 2
DCSTA:             RMB 1
NMIFLG:            RMB 1
DNMIVC:            RMB 2
RDYTMR:            RMB 1
DRGRAM:            RMB 1
DiskTrackImage:    RMB 1
DNAMBF:            RMB 11      * formatted DECB 8.3 filename
DiskSearchName:    RMB 2
DiskFreeDirSec:    RMB 1
DiskFreeDirOff:    RMB 1
DiskDirSector:     RMB 1
DiskFileType:      RMB 1
DiskCurrentGran:   RMB 1
DiskNextGran:      RMB 1
DiskLastGran:      RMB 1
DiskGranuleEnd:    RMB 1
DiskBufferPtr:     RMB 2
DiskReadLastLen:   RMB 2
DiskReadLimit:     RMB 2
DiskStreamMode:    RMB 1       * 0=none, 1=sequential read, 2=write
DiskWriteAny:      RMB 1
DiskOutputFileType: RMB 1
DiskOutputASCII:   RMB 1
DiskSaveStart:     RMB 2
DiskSaveEnd:       RMB 2
DiskSaveExec:      RMB 2
DiskSaveWord:      RMB 2
DiskSaveLastLen:   RMB 2
DiskSaveSectors:   RMB 1
DiskSaveListPos:   RMB 1
DiskSaveListCnt:   RMB 1
DiskGranuleList:   RMB MAXSAVEGRAN
DiskApiStack:      RMB 2
DiskLoadOffset:    RMB 2
DiskLoadExec:      RMB 2
DiskNameSource:    RMB 2
DiskNMIInstalled:  RMB 1
DiskNMIVector:     RMB 2
DiskSavedNMI:      RMB 3
DiskInitMagic:     RMB 4
DiskBuffer:        RMB SECLEN
DiskWorkspaceEnd:

DECB_DiskLibraryEnd:
