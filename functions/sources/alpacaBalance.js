if(secrets.alpacaKey==""||
  secrets.alpacaSecret==""){
  throw Error(" need Alpaca key ")
}

const alpacaRequest=Functions.makeHttpRequest({
  url:"https://paper-api.alpaca.markets/v2/account",
  headers: {
    accept: 'application/json',
    'APCA-API-KEY-ID': secrets.alpacaKey,
    'APCA-API-SECRET-KEY': secrets.alpacaSecret
  }
})
const [response]=await Promise.all([alpacaRequest])

const portfolioBalance=response.data.portfolio_value
console.log("Alpaca balance: ",portfolioBalance)
return Functions.encodeUnit256(Math.floor(portfolioBalance*100))


