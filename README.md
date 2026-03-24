# BaseModelicaLibraryTesting.jl

[![Build Status][build-badge-svg]][build-action-url]
[![MSL Test Reports][msl-badge-svg]][msl-pages-url]

Experimental Base Modelica library testing based on Julia.

## Library Testing

For a given Modelica library test

1. Base Modelica export ([OpenModelica][openmodelica-url],
   [OMJulia.jl][omjuliajl-url])
2. Base Modelica parsing ([BaseModelica.jl][basemodelicajl-url])
3. ODE simulation ([ModelingToolkit.jl][modelingtoolkitjl-url],
   [DifferentialEquations.jl][diffeqjl-url])
4. Validating simulation results

## Usage

```julia
main(
  library = "<Modelica library name>",
  version = "<Modelica library version>",
  filter = "<Modelica class filter>",
  omc_exe = "path/to/omc",
  ref_root = "path/to/ReferenceResults"
)
```

If reference results are available provide the path via `ref_root`.

### Example - Testing the Modelica Standard Library v4.1.0

For example, for the Modelica Standard Library v4.1.0 reference results can be obtained by cloning the [MAP-LIB_ReferenceResults][map-lib-ref-results-url] repository:`

```bash
git clone --depth 1 -b v4.1.0 https://github.com/modelica/MAP-LIB_ReferenceResults
```

Run the library testing for the ChuaCircuit example of the Modelica Standard
Library v4.1.0 with:

```julia
using BaseModelicaLibraryTesting

main(
  library = "Modelica",
  version = "4.1.0",
  filter = "Modelica.Electrical.Analog.Examples.ChuaCircuit",
  omc_exe = "omc",
  ref_root = "MAP-LIB_ReferenceResults"
)
```

Preview the generated HTML report at `main/Modelica/4.1.0/report.html`.

### Changing the ODE Solver

By default the simulation uses `Rodas5P()`. To switch to a different solver,
call `configure_simulate!` before `main`:

```julia
using BaseModelicaLibraryTesting
using DifferentialEquations

configure_simulate!(solver = FBDF())

main(
  library = "Modelica",
  version = "4.1.0",
  omc_exe = "omc",
  ref_root = "MAP-LIB_ReferenceResults"
)
```

Any SciML-compatible ODE/DAE algorithm (e.g. `QNDF()`, `Rodas4()`) can be
passed to `solver`.

```bash
python -m http.server -d results/main/Modelica/4.1.0/
```

## GitHub Actions — Manual MSL Test

The [MSL Test & GitHub Pages][msl-action-url] workflow runs automatically every
day at 03:00 UTC. It can also be triggered manually from the GitHub Actions UI:

1. Go to **Actions → MSL Test & GitHub Pages**
2. Click **Run workflow**
3. Fill in the options and click **Run workflow**

The following inputs are available:

| Input | Default | Description |
| ----- | ------- | ----------- |
| `library` | `Modelica` | Modelica library name |
| `lib_version` | `4.1.0` | Library version to test |
| `bm_version` | `main` | BaseModelica.jl branch, tag, or version |
| `bm_options` | `scalarize,moveBindings,inlineFunctions` | Comma-separated `--baseModelicaOptions` passed to OpenModelica during Base Modelica export |
| `filter` | `^(?!Modelica\.Clocked)` | Julia regex to restrict which models are tested (empty string runs all models) |
| `solver` | `Rodas5P` | Any `DifferentialEquations.jl` algorithm name (e.g. `Rodas5P`, `Rodas5Pr`, `FBDF`) |

Results are published to [GitHub Pages][msl-pages-url] under
`results/<bm_version>/<library>/<lib_version>/`.

## License

This package is available under the [OSMC-PL License][osmc-license-file] and the
[AGPL-3.0 License][agpl-file]. See the [OSMC-License.txt][osmc-license-file]
file for details.

[build-badge-svg]: https://github.com/OpenModelica/BaseModelicaLibraryTesting.jl/actions/workflows/CI.yml/badge.svg?branch=main
[build-action-url]: https://github.com/OpenModelica/BaseModelicaLibraryTesting.jl/actions/workflows/CI.yml?query=branch%3Amain
[msl-badge-svg]: https://github.com/OpenModelica/BaseModelicaLibraryTesting.jl/actions/workflows/msl-test.yml/badge.svg?branch=main
[msl-action-url]: https://github.com/OpenModelica/BaseModelicaLibraryTesting.jl/actions/workflows/msl-test.yml
[msl-pages-url]: https://openmodelica.github.io/BaseModelicaLibraryTesting.jl/
[openmodelica-url]: https://openmodelica.org/
[basemodelicajl-url]: https://github.com/SciML/BaseModelica.jl
[modelingtoolkitjl-url]: https://github.com/SciML/ModelingToolkit.jl
[diffeqjl-url]: https://github.com/SciML/DifferentialEquations.jl
[omjuliajl-url]: https://github.com/OpenModelica/OMJulia.jl
[map-lib-ref-results-url]: https://github.com/modelica/MAP-LIB_ReferenceResults/tree/v4.1.0
[osmc-license-file]: OSMC-License.txt
[agpl-file]: LICENSE
