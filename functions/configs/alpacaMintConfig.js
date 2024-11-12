const fs=require('fs');
 const {Location,ReturnType,codeLanguage}=require('@chainlink/functions-toolkit');
const  ALPACA_API_KEY = "PKNZ5LYDOLTWQR0CS8ZT";
const  ALPACA_SECRET_KEY = "4c1s3CCwN3iGguj5w7GJYYJ4XcscG35WReepU4Vq";

 const requestConfig = {
    source: fs.readFileSync('../../functions/sources/alpacaBalance.js'),
    codeLocation:Location.Inline,
    secrets:{ alpacaKey: ALPACA_API_KEY,
       alpacaSecret: ALPACA_SECRET_KEY}, 
       secretsLocation: Location.DONHosted,
     args:[],
     codeLanguage:codeLanguage.Javascript,
     expectedReturnType: ReturnType.uint256  
      
      };
      module.exports = requestConfig;




 