# BaseModelicaLibraryTesting

[![Build Status](https://github.com/OpenModelica/BaseModelicaLibraryTesting.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/OpenModelica/BaseModelicaLibraryTesting.jl/actions/workflows/CI.yml?query=branch%3Amain)

Experimental Base Modelica library testing based on Julia.

## Library Testing

For a given Modelica library test

1. Base Modelica export ([OpenModelica][openmodelica-url],
   [OMJulia.jl][omjuliajl-url])
2. Base Modelica parsing ([BaseModelica.jl][basemodelicajl-url])
3. ODE simulation ([ModelingToolkit.jl][modelingtoolkitjl-url],
   [DifferentialEquations.jl][diffeqjl-url])
4. Validating simulation results

## License

This package is available under the [OSMC-PL License][osmc-license-file] and the
[AGPL-3.0 License][agpl-file]. See the [OSMC-License.txt][osmc-license-file]
file for details.

[openmodelica-url]: https://openmodelica.org/
[omjuliajl-url]: https://github.com/OpenModelica/OMJulia.jl
[osmc-license-file]: OSMC-License.txt
[agpl-file]: LICENSE
[basemodelicajl-url]: https://github.com/SciML/BaseModelica.jl
[modelingtoolkitjl-url]: https://github.com/SciML/ModelingToolkit.jl
[diffeqjl-url]: https://github.com/SciML/DifferentialEquations.jl
