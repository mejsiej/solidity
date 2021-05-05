{
   let x := 0
   let y := 1
   sstore(x, y)
   f()
   sstore(x, y)
   function f() {
      // prevent inlining
      f()
      return(0, 0)
   }
  }
// ----
// step: redundantStoreEliminator
//
// {
//     let x := 0
//     let y := 1
//     f()
//     sstore(x, y)
//     function f()
//     {
//         f()
//         return(0, 0)
//     }
// }
