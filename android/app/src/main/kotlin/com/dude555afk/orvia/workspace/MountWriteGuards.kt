package com.dude555afk.orvia.workspace

import java.io.File

internal object MountWriteGuards {
    private const val MARKER = "# orvia-mount-readonly-guard"
    private const val CONFIG = "/run/orvia/mount-readonly-prefixes"
    private val commands = listOf("touch", "tee", "cp", "mv", "mkdir", "rm", "rmdir", "ln", "dd")

    fun install(rootfs: File, mounts: List<BindMount>) {
        val prefixes = mounts.filter { it.readOnly }.map { it.guest }
        val config = File(rootfs, CONFIG.removePrefix("/"))
        val bin = File(rootfs, "usr/local/bin").canonicalFile
        if (prefixes.isEmpty()) {
            if (!config.exists()) return
            for (name in commands) {
                val wrapper = File(bin, name)
                if (isOurWrapper(wrapper)) wrapper.delete()
            }
            config.delete()
            return
        }
        config.parentFile!!.mkdirs()
        config.writeText(prefixes.joinToString("\n", postfix = "\n"))
        bin.mkdirs()
        for (name in commands) {
            val wrapper = File(bin, name)
            if (wrapper.canonicalFile != wrapper.absoluteFile) continue
            if (wrapper.exists() && !isOurWrapper(wrapper)) continue
            val script = commandScript(name)
            if (!wrapper.exists() || wrapper.readText() != script) wrapper.writeText(script)
            check(wrapper.setExecutable(true, false)) { "Cannot install mount write guard" }
        }
    }

    private fun isOurWrapper(file: File): Boolean {
        if (!file.isFile || file.canonicalFile != file.absoluteFile) return false
        return file.inputStream().use { input ->
            val prefix = ByteArray(80)
            val size = input.read(prefix)
            size > 0 && String(prefix, 0, size, Charsets.UTF_8).startsWith("#!/bin/sh\n$MARKER\n")
        }
    }

    internal fun commandScript(name: String, config: String = CONFIG): String {
        require(name in commands)
        val quotedConfig = "'" + config.replace("'", "'\"'\"'") + "'"
        val dollar = "$"
        return """#!/bin/sh
            |$MARKER
            |cfg=$quotedConfig
            |check_target() {
            |    [ -f "${dollar}cfg" ] || return 0
            |    resolved=${dollar}(PATH=/usr/bin:/bin realpath -m -- "${dollar}1" 2>/dev/null) ||
            |        resolved=${dollar}(PATH=/usr/bin:/bin readlink -f -- "${dollar}1" 2>/dev/null) || resolved="${dollar}1"
            |    case "${dollar}resolved" in /*) ;; *) resolved="${dollar}PWD/${dollar}resolved";; esac
            |    while IFS= read -r prefix; do
            |        [ -n "${dollar}prefix" ] || continue
            |        case "${dollar}resolved" in
            |            "${dollar}prefix"|"${dollar}prefix"/*)
            |                printf '%s\n' "$name: ${dollar}1: read-only mounted folder; enable writes in Environment settings" >&2
            |                exit 1;;
            |        esac
            |    done < "${dollar}cfg"
            |}
            |for arg do
            |    case "${dollar}arg" in
            |        -*) continue;;
            |    esac
            |    if [ "$name" = dd ]; then
            |        case "${dollar}arg" in of=*) check_target "${dollar}{arg#of=}";; esac
            |    else
            |        check_target "${dollar}arg"
            |    fi
            |done
            |PATH=/usr/bin:/bin exec $name "${dollar}@"
            |""".trimMargin()
    }
}
