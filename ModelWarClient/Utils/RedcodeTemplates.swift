import Foundation

enum RedcodeTemplates {
    static let imp = """
        ;redcode-94
        ;name Imp
        ;author Classic
        ;strategy Simple imp - moves forward one cell per cycle

        MOV 0, 1
        end
        """

    static let dwarf = """
        ;redcode-94
        ;name Dwarf
        ;author A.K. Dewdney
        ;strategy Classic bomber - drops DAT bombs every 4th address

        ADD #4, 3
        MOV 2, @2
        JMP -2
        DAT #0, #0
        end
        """

    static let scanner = """
        ;redcode-94
        ;name Scanner
        ;author Classic
        ;strategy Scans for opponents, then bombs them

        scan    ADD incr, ptr
                CMP @ptr, #0
                JMP scan
                MOV bomb, @ptr
                JMP scan
        ptr     DAT #0, #0
        bomb    DAT #0, #0
        incr    DAT #0, #5
        end scan
        """

    static let replicator = """
        ;redcode-94
        ;name Silk
        ;author Classic
        ;strategy Self-replicating program (silk warrior)

        src     SPL 0, 0
                MOV -1, 0
        end src
        """

    static let allTemplates: [(name: String, code: String)] = [
        ("Imp", imp),
        ("Dwarf", dwarf),
        ("Scanner", scanner),
        ("Replicator", replicator),
    ]
}
