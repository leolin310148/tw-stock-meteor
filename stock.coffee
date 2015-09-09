StockCollection = new Mongo.Collection("Stocks")
TseT00Price = new Mongo.Collection("TseT00Price")
StockHolderCollection = new Mongo.Collection("StockHolders")

if Meteor.isClient
  Accounts.ui.config({passwordSignupFields: "USERNAME_ONLY"})

  angular.module('StockApp', ['angular-meteor'])
  .controller('StockCtrl', ['$scope', '$meteor', '$rootScope'
      ($scope, $meteor, $rootScope)->
        refreshStocksInSearch = ()->
          $scope.stocksInSearch = $meteor.collection ()->
            StockCollection.find($scope.getReactively('keywordQuery'), {sort: {ch: 1}})
        refreshStocksInSearch()

        $scope.$watch 'searchStockKeyword', ()->
          if($scope.searchStockKeyword && $scope.searchStockKeyword.length > 0)
            $scope.keywordQuery =
              $or: [
                {ch: {$regex: new RegExp("^" + $scope.searchStockKeyword)}},
                {name: {$regex: new RegExp($scope.searchStockKeyword)}}
              ]
          else
            $scope.keywordQuery = undefined

        $scope.t00 = $meteor.collection ()-> TseT00Price.find({})
        $scope.stockPricesToShow = $meteor.collection ()-> StockCollection.find({subscribers: Meteor.userId()})

        $scope.addToSubscribe = (stock)->
          stock.subscribers.push(Meteor.userId())
          refreshStocksInSearch()
        $scope.isSubscribed = (stock)->
          _(stock.subscribers).contains(Meteor.userId())
        $scope.unsubscribe = (stock)->
          stock.subscribers = _(stock.subscribers).without(Meteor.userId())
          refreshStocksInSearch()

        $scope.getPriceCss = (price)->
          if price
            if price.diff == 0 then return "price-no"
            if price.diff > 0 then return "price-up"
            if price.diff < 0 then return "price-down"

        refreshUserProfile = ()->
          if(Meteor.userId())
            $meteor.call("getCurrentUserProfile", Meteor.userId()).then((profile)->
              $scope.userProfile = profile
            )
          else
            $scope.userProfile = null
        $meteor.autorun($rootScope, refreshUserProfile)

        #買進
        $scope.doBuying = (buyingCount, stock)->
          selector = {
            userId: Meteor.userId(),
            ch: stock.ch,
          }
          holdingStock = StockHolderCollection.findOne(selector)
          if(holdingStock )
            count = holdingStock.count + buyingCount
            StockHolderCollection.update({_id: holdingStock._id}, {$set: {count: count}})
          else
            selector.count = buyingCount
            selector.name = stock.name
            StockHolderCollection.insert(selector)
          $scope.buyingStock = null
          moneyCost = 0 - buyingCount * 1000 * stock.info.currentPrice
          Meteor.call('addUserMoney', Meteor.userId(), moneyCost)
          refreshUserProfile()

        #賣出
        $scope.doSelling = (sellingCount, sellingStock)->
          selector = {_id: sellingStock._id}
          if(sellingCount == sellingStock.count)
            StockHolderCollection.remove(selector)
          else
            countToSave = sellingStock.count = sellingCount
            StockHolderCollection.update(selector, {$set: {count: countToSave}})

          price = StockCollection.findOne({ch: sellingStock.ch}).info.currentPrice
          $scope.sellingStock = null
          moneyCost = sellingCount * 1000 * price
          Meteor.call('addUserMoney', Meteor.userId(), moneyCost)
          refreshUserProfile()

        $scope.startBuying = (stock)->
          $scope.buyingStock = stock
          $scope.buyingCount = null

        $scope.startSelling = (stock)->
          $("#sellingInput").attr("max", stock.count)
          $scope.sellingStock = stock
          $scope.sellingCount = null

        $scope.cancelBuyOrSell = ()->
          $scope.buyingStock = null
          $scope.sellingStock = null

        #持股
        $scope.holdingStocks = $meteor.collection ()->
          StockHolderCollection.find({userId: Meteor.userId()})
    ])


if Meteor.isServer
  Accounts.onCreateUser((user)->
    user.profile = {money: 0}
    user
  )

  Meteor.startup ()->
    Meteor.methods({
      getCurrentUserProfile: (id)->
        user = Meteor.users.findOne({_id: id})
        if(!user)then return undefined
        return user.profile
      addUserMoney: (id, moneyToAdd)->
        user = Meteor.users.findOne({_id: id})
        moneyToSave = user.profile.money + moneyToAdd
        Meteor.users.update({_id: user._id}, {$set: {profile: {money: moneyToSave}}})
    })

    Meteor.users.find().forEach((user)->
      if(!user.profile)
        Meteor.users.update({_id: user._id}, {$set: {profile: {money: 0}}})
    )


    if TseT00Price.find({}).count() == 0
      TseT00Price.insert({ch: "t00", info: {}})
    Meteor.setInterval(()->
      Meteor.http.get "http://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=tse_t00.tw&json=1&delay=0", (err, res)->
        TseT00Price.update(
          {ch: "t00"},
          {$set: {info: mapPriceInfo(JSON.parse(res.content).msgArray[0])}}
        )
    , 2500)
    Meteor.http.get "http://api.leolin.me/stocks", (err, res)->
      stocks = JSON.parse(res.content)
      stocks.forEach (stock)-> stock.ch = stock.ch.replace(".tw", "")
      stocks
      .filter (stock)-> StockCollection.find({ch: stock.ch}).count() == 0
      .map (stock)-> {ch: stock.ch, name: stock.n, info: {}, subscribers: []}
      .forEach (stock)-> StockCollection.insert stock

      chs = stocks.map((stock)-> stock.ch)
      Meteor.setInterval(()->
        Meteor.http.post "http://api.leolin.me/prices", {data: chs}, (err, res)->
          JSON.parse(res.content).forEach (priceInfo)->
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
