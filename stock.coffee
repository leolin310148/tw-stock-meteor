StockCollection = new Mongo.Collection("Stocks")
TseT00Price = new Mongo.Collection("TseT00Price")
if Meteor.isClient
  Accounts.ui.config({passwordSignupFields: "USERNAME_ONLY"})

  angular.module('StockApp', ['angular-meteor'])
  .controller('StockCtrl', ['$scope', '$meteor'
      ($scope, $meteor)->
        $scope.stocksInSearch = $meteor.collection ()->
          StockCollection.find($scope.getReactively('keywordQuery'), {sort: {ch: 1}})

        $scope.$watch 'searchStockKeyword', ()->
          if($scope.searchStockKeyword && $scope.searchStockKeyword.length > 0)
            $scope.keywordQuery =
              $or: [
                {ch: {$regex: new RegExp("^" + $scope.searchStockKeyword)}},
                {name: {$regex: new RegExp($scope.searchStockKeyword)}}
              ]

        $scope.t00 = $meteor.collection ()-> TseT00Price.find({})
        $scope.stockPricesToShow = $meteor.collection ()-> StockCollection.find({subscribers: Meteor.userId()})
        $scope.addToSubscribe = (stock)-> stock.subscribers.push(Meteor.userId())
        $scope.isSubscribed = (stock)-> _(stock.subscribers).contains(Meteor.userId())
        $scope.unsubscribe = (stock)-> stock.subscribers = _(stock.subscribers).without(Meteor.userId())

        $scope.getPriceCss = (price)->
          if price
            if price.diff == 0 then return "price-no"
            if price.diff > 0 then return "price-up"
            if price.diff < 0 then return "price-down"

    ])

if Meteor.isServer
  Meteor.startup ()->
    if TseT00Price.find({}).count() == 0
      TseT00Price.insert({ch: "t00", info: {}})
    Meteor.setInterval(()->
      Meteor.http.get "http://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=tse_t00.tw&json=1&delay=0", (err, res)->
        TseT00Price.update(
          {ch: "t00"},
          {$set: {info: mapPriceInfo(JSON.parse(res.content).msgArray[0])}}
        )
    , 2500)
    Meteor.http.get "http://mis.twse.com.tw/stock/api/getIndustry.jsp", (err, res)->
      JSON.parse(res.content).tse.forEach (industry)->
        Meteor.http.get "http://mis.twse.com.tw/stock/api/getCategory.jsp?ex=tse&i=" + industry.code, (err, res)->
          stocks = JSON.parse(res.content).msgArray.filter (stock)-> stock.ch.length <= 7
          stocks.forEach (stock)-> stock.ch = stock.ch.replace(".tw", "")
          stocks
          .filter (stock)-> StockCollection.findOne({ch: stock.ch}) == undefined
          .map (stock)-> {ch: stock.ch, name: stock.n, info: {}, subscribers: []}
          .forEach (stock)-> StockCollection.insert stock

          if stocks.length > 0
            chs = stocks.map((stock)-> "tse_" + stock.ch + ".tw").reduce((ch1, ch2)-> ch1 + "|" + ch2)
            config = {
              headers: {
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                'Accept-Encoding': 'gzip, deflate, sdch'
                'Accept-Language': 'zh-TW,zh;q=0.8,en-US;q=0.6,en;q=0.4,zh-CN;q=0.2,de;q=0.2'
                'Connection': 'keep-alive'
                'Host': 'mis.twse.com.tw'
                'Upgrade-Insecure-Requests': '1'
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.157 Safari/537.36'
              }
            }
            Meteor.setInterval(()->
              Meteor.http.get "http://mis.twse.com.tw/stock/fibest.jsp", config, (err, res)->
                cookie = eval(res.headers['set-cookie'])[0].split(';')[0]
                configWithCookie = {
                  headers: {
                    'Connection': 'keep-alive'
                    'Host': 'mis.twse.com.tw'
                    'Upgrade-Insecure-Requests': '1'
                    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.157 Safari/537.36'
                    'Cookie': cookie
                    'Referer': 'http://mis.twse.com.tw/stock/fibest.jsp'
                  }
                }
                url = "http://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=" + chs + "&json=1&delay=0"
                Meteor.http.get url, configWithCookie, (err, res)->
                  if(res == null)
                    console.log(url, err)
                  else
                    JSON.parse(res.content).msgArray.forEach (priceInfo)->
                      StockCollection.update(
                        {ch: priceInfo.ch.replace(".tw", "")},
                        {$set: {info: mapPriceInfo(priceInfo, true)}}
                      )

            , 10000)

toFloatAntToFixed = (value, fix)->
  value = parseFloat(value)
  value.toFixed(if fix then getFixByPrice(value) else 2)

getFixByPrice = (price)->
  price = parseFloat(price)
  if price >= 1000 then return 0
  if price >= 100 then return 1
  2

getDiff = (priceInfo, fix)->
  z = parseFloat(priceInfo.z)
  (z - parseFloat(priceInfo.y)).toFixed(if fix then getFixByPrice(z) else 2)

getDiffPercent = (priceInfo)-> (getDiff(priceInfo) * 100.0 / parseFloat(priceInfo.y)).toFixed(1)

mapPriceInfo = (priceInfo, fix)->
  y: priceInfo.y #昨收
  diff: getDiff(priceInfo, fix) #漲跌
  diffPercent: getDiffPercent(priceInfo) #漲跌幅
  openPrice: toFloatAntToFixed(priceInfo.o) #開盤
  hiPrice: toFloatAntToFixed(priceInfo.h) #最高
  loPrice: toFloatAntToFixed(priceInfo.l) #最低
  currentPrice: toFloatAntToFixed(priceInfo.z, fix) #成交價
  time: priceInfo.tlong #時間
  currentVolume: priceInfo.tv #當盤成交量
  totalVolume: priceInfo.v #當日成交量
