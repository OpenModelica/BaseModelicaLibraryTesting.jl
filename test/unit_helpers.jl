@testset "Unit tests" begin

    @testset "_clean_var_name" begin
        # Standard MTK form: var"name"(t)
        @test _clean_var_name("var\"C1.v\"(t)") == "C1.v"
        # Without (t)
        @test _clean_var_name("var\"C1.v\"") == "C1.v"
        # Plain name with (t) suffix
        @test _clean_var_name("C1.v(t)") == "C1.v"
        # Plain name, no annotation
        @test _clean_var_name("x") == "x"
        # Leading/trailing whitespace is stripped
        @test _clean_var_name("  foo(t)  ") == "foo"
        # ₊ hierarchy separator is preserved (it is the job of _normalize_var)
        @test _clean_var_name("var\"C1₊v\"(t)") == "C1₊v"
    end

    @testset "_normalize_var" begin
        # Reference-CSV side: plain dot-separated name
        @test _normalize_var("C1.v")             == "c1.v"
        @test _normalize_var("L.i")              == "l.i"
        # MTK side with ₊ hierarchy separator and (t) annotation
        @test _normalize_var("C1₊v(t)")          == "c1.v"
        # MTK side with var"..." quoting
        @test _normalize_var("var\"C1₊v\"(t)")   == "c1.v"
        # Already normalized input
        @test _normalize_var("c1.v")             == "c1.v"
        # Multi-level hierarchy
        @test _normalize_var("a₊b₊c(t)")        == "a.b.c"
    end

    @testset "_ref_csv_path" begin
        mktempdir() do dir
            model   = "Modelica.Electrical.Analog.Examples.ChuaCircuit"
            csv_dir = joinpath(dir, "Modelica", "Electrical", "Analog",
                               "Examples", "ChuaCircuit")
            mkpath(csv_dir)
            csv_file = joinpath(csv_dir, "ChuaCircuit.csv")
            write(csv_file, "")
            @test _ref_csv_path(dir, model) == csv_file
            @test _ref_csv_path(dir, "Modelica.NotExisting") === nothing
        end
    end

    @testset "_read_ref_csv" begin
        mktempdir() do dir
            csv = joinpath(dir, "test.csv")

            # Quoted headers (MAP-LIB format)
            write(csv, "\"time\",\"C1.v\",\"L.i\"\n0,4,0\n0.5,3.5,0.1\n1,3.0,0.2\n")
            times, data = _read_ref_csv(csv)
            @test times        ≈ [0.0, 0.5, 1.0]
            @test data["C1.v"] ≈ [4.0, 3.5, 3.0]
            @test data["L.i"]  ≈ [0.0, 0.1, 0.2]
            @test !haskey(data, "\"time\"")   # quotes must be stripped from keys

            # Unquoted headers
            write(csv, "time,x,y\n0,1,2\n1,3,4\n")
            times2, data2 = _read_ref_csv(csv)
            @test times2     ≈ [0.0, 1.0]
            @test data2["x"] ≈ [1.0, 3.0]
            @test data2["y"] ≈ [2.0, 4.0]

            # Empty file → empty collections
            write(csv, "")
            t0, d0 = _read_ref_csv(csv)
            @test isempty(t0)
            @test isempty(d0)

            # Blank lines between data rows are ignored
            write(csv, "time,v\n0,1\n\n1,2\n\n")
            times3, data3 = _read_ref_csv(csv)
            @test times3     ≈ [0.0, 1.0]
            @test data3["v"] ≈ [1.0, 2.0]
        end
    end

end  # "Unit tests"
