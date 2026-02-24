# ── Phase 1: Base Modelica export via OMC ─────────────────────────────────────

"""
    run_export(omc, model, model_dir, bm_path) → (success, time, error)

Export the Base Modelica representation of `model` via the given OMC session.
Writes a `<model>_export.log` file in `model_dir`.
The `.bmo` file is written to `bm_path` (which must use forward slashes).
"""
function run_export(omc::OMJulia.OMCSession, model::String, model_dir::String,
                    bm_path::String)::Tuple{Bool,Float64,String}
    bm_path_esc = replace(bm_path, "\"" => "\\\"")

    export_success = false
    export_time    = 0.0
    export_error   = ""

    t0 = time()
    try
        result = sendExpression(omc,
            """writeFile("$bm_path_esc", OpenModelica.Scripting.instantiateModel($model))""")
        export_time = time() - t0

        if result == false
            export_error = sendExpression(omc, "getErrorString()")
        elseif !isfile(bm_path) || filesize(bm_path) == 0
            errmsg = sendExpression(omc, "getErrorString()")
            export_error = isempty(errmsg) ?
                "Base Modelica file missing or empty at: $bm_path" : errmsg
        else
            sendExpression(omc, "getErrorString()")    # drain any non-fatal warnings
            export_success = true
        end
    catch e
        export_time  = time() - t0
        export_error = sprint(showerror, e, catch_backtrace())
    end

    open(joinpath(model_dir, "$(model)_export.log"), "w") do f
        println(f, "Model:   $model")
        println(f, "Time:    $(round(export_time; digits=3)) s")
        println(f, "Success: $export_success")
        isempty(export_error) || println(f, "\n--- Error ---\n$export_error")
    end

    return export_success, export_time, export_error
end
